"""Validate signed Jerd apps, runtime receipts, update metadata, and release packages."""
import base64
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET

from release_common import FEED_URL, REPOSITORY, ROOT, SPARKLE, SPARKLE_ACCOUNT, digest, is_macho, local_dependency, macho_details, parallel_each, regular_file, run, version_tuple
from release_runtimes import payloads


def verify_binary(path, team):
    requirement = ('anchor apple generic and certificate leaf[subject.OU] = "' + team
                   + '" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
    # A leading '=' makes codesign parse inline text instead of opening a file.
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + requirement, path)
    result = subprocess.run(["/usr/bin/codesign", "-d", "--verbose=4", str(path)], capture_output=True, text=True)
    if result.returncode or "(runtime)" not in result.stderr or "Timestamp=" not in result.stderr:
        raise ValueError("Missing hardened runtime or secure timestamp: " + str(path))
    result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)], capture_output=True)
    if result.stdout.strip() and plistlib.loads(result.stdout).get("com.apple.security.get-task-allow"):
        raise ValueError("Debug entitlement in release: " + str(path))


def verify_app(app, team, minimum, notarized=True):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected_key = re.search(r'JERD_UPDATE_PUBLIC_KEY: "([^"]+)"', (ROOT / "project.yml").read_text()).group(1)
    if info.get("CFBundleIdentifier") != "dev.jerd.app" or info.get("SUFeedURL") != FEED_URL:
        raise ValueError("The app has the wrong identity or update feed")
    if info.get("SUPublicEDKey") != expected_key or len(base64.b64decode(expected_key, validate=True)) != 32:
        raise ValueError("The app has the wrong Sparkle key")
    if any(info.get(key) is not True for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"]):
        raise ValueError("Required Sparkle signature checks are disabled")
    if info.get("SUSignedFeedFailureExpirationInterval") != 0 or info.get("SUAllowsAutomaticUpdates") is not False:
        raise ValueError("Unexpected Sparkle signature expiry or automatic installation policy")
    if info.get("LSMinimumSystemVersion") != minimum:
        raise ValueError("The app has an unexpected macOS requirement")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    binaries = [app / "Contents/MacOS/Jerd", app / "Contents/MacOS/JerdCLI",
                app / "Contents/Library/LaunchServices/JerdHelper"]
    for group, _, _, entry, folder, _, receipt, key in payloads(app / "Contents/Resources"):
        fingerprint = hashlib.sha256(json.dumps(receipt[key], sort_keys=True).encode()).hexdigest()[:16]
        base = entry.get("id") or f"{entry['name']}-{entry['tag']}-arm64"
        if entry.get("installationID") != base + "-release-" + fingerprint:
            raise ValueError("The signed payload installation ID does not match its files")
        if receipt.get("releaseSigning", {}).get("teamID") != team:
            raise ValueError("The runtime receipt has the wrong signing team")
        for name in receipt[key]:
            path = folder / name
            if not is_macho(path):
                continue
            details = macho_details(path)
            for dependency in details["dependencies"]:
                local_dependency(path, dependency, folder, details["rpaths"])
            if version_tuple(details["minimum"]) > version_tuple(minimum):
                raise ValueError("A runtime requires a newer macOS version: " + name)
            binaries.append(path)
    parallel_each(lambda path: verify_binary(path, team), binaries)
    if run("/usr/bin/lipo", "-archs", binaries[0]) != "arm64":
        raise ValueError("The release must target Apple Silicon")
    if notarized:
        run("/usr/bin/xcrun", "stapler", "validate", app)
        run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app)
    return info


def verify_sparkle_key():
    expected = re.search(r'JERD_UPDATE_PUBLIC_KEY: "([^"]+)"', (ROOT / "project.yml").read_text()).group(1)
    actual = run(SPARKLE / "generate_keys", "--account", SPARKLE_ACCOUNT, "-p")
    if actual != expected:
        raise ValueError("The Keychain signing account does not match the app's Sparkle public key")


def verify_feed(path, archive, info, minimum, repository):
    verify_sparkle_key()
    run(SPARKLE / "sign_update", "--account", SPARKLE_ACCOUNT, "--verify", path)
    namespace = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    items = ET.parse(path).findall("./channel/item")
    matches = [item for item in items if item.findtext("s:version", namespaces=namespace) == info["CFBundleVersion"]]
    if len(matches) != 1:
        raise ValueError("The candidate feed has no unique entry for this build")
    item = matches[0]
    if item.findtext("s:shortVersionString", namespaces=namespace) != info["CFBundleShortVersionString"]:
        raise ValueError("Feed version differs from app version")
    if item.findtext("s:minimumSystemVersion", namespaces=namespace) != minimum:
        raise ValueError("Feed macOS requirement differs from the release")
    if item.findtext("s:hardwareRequirements", namespaces=namespace) != "arm64":
        raise ValueError("The feed does not require Apple Silicon")
    enclosure = item.find("enclosure")
    expected_url = f"https://github.com/{repository}/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
    if enclosure is None or enclosure.get("url") != expected_url or enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("The feed does not match the archive")
    signature = enclosure.get("{" + namespace["s"] + "}edSignature", "")
    run(SPARKLE / "sign_update", "--account", SPARKLE_ACCOUNT, "--verify", archive, signature)


def symbol_uuids(path):
    output = run("/usr/bin/xcrun", "dwarfdump", "--uuid", path)
    values = re.findall(r"UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)", output)
    if not values:
        raise ValueError("No debug UUID found: " + str(path))
    return set(values)


def verify_symbols(app, symbols):
    for binary, bundle in [("Contents/MacOS/Jerd", "Jerd.app.dSYM"),
                           ("Contents/MacOS/JerdCLI", "JerdCLI.dSYM"),
                           ("Contents/Library/LaunchServices/JerdHelper", "JerdHelper.dSYM")]:
        symbol = symbols / bundle / "Contents/Resources/DWARF" / pathlib.Path(binary).name
        if symbol_uuids(app / binary) != symbol_uuids(symbol):
            raise ValueError("The retained debug symbols do not match " + binary)


def validate(directory):
    directory = pathlib.Path(directory).resolve()
    manifest = json.loads((directory / "release.json").read_text())
    if manifest.get("schemaVersion") != 1:
        raise ValueError("Unknown release record format")
    if manifest.get("repository") != REPOSITORY or manifest.get("architecture") != "arm64":
        raise ValueError("Unexpected release repository or architecture")
    if not re.fullmatch(r"[A-Z0-9]{10}", manifest.get("teamID", "")):
        raise ValueError("Invalid release team")
    if not re.fullmatch(r"[a-f0-9]{40}", manifest.get("sourceCommit", "")):
        raise ValueError("Invalid source commit")
    if not re.fullmatch(r"[1-9]\d*", manifest.get("build", "")):
        raise ValueError("Invalid release build")
    version_tuple(manifest["version"])
    if manifest.get("dmg") != f"Jerd-{manifest['version']}.dmg" or manifest.get("symbols") != f"Jerd-{manifest['version']}-{manifest['build']}.dSYMs.zip":
        raise ValueError("Invalid release artifact name")
    required = {manifest["dmg"], manifest["symbols"], "appcast.xml", "release-notes.md"}
    if set(manifest["files"]) != required:
        raise ValueError("The release record has missing or unexpected artifacts")
    for name, expected in manifest["files"].items():
        if pathlib.PurePosixPath(name).name != name or digest(regular_file(directory, name)) != expected:
            raise ValueError("The release file changed: " + name)
    app = directory / "export/Jerd.app"
    dmg = directory / manifest["dmg"]
    info = verify_app(app, manifest["teamID"], manifest["minimumMacOS"])
    if info["CFBundleVersion"] != manifest["build"] or info["CFBundleShortVersionString"] != manifest["version"]:
        raise ValueError("The app version differs from the release record")
    verify_symbols(app, directory / "symbols")
    # Verify the actual archive to be published, as well as the retained source symbols.
    with tempfile.TemporaryDirectory(prefix="jerd-symbols-") as temp:
        with zipfile.ZipFile(directory / manifest["symbols"]) as archive:
            members = archive.infolist()
            if len(members) > 1000 or sum(x.file_size for x in members) > 1024 * 1024 * 1024:
                raise ValueError("Debug symbols exceed extraction limits")
            for member in members:
                path = pathlib.PurePosixPath(member.filename)
                if path.is_absolute() or ".." in path.parts or (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError("Unsafe path in debug symbols")
            archive.extractall(temp)
        verify_symbols(app, pathlib.Path(temp) / "symbols")
    verify_feed(directory / "appcast.xml", dmg, info, manifest["minimumMacOS"], manifest["repository"])
    run("/usr/bin/codesign", "--verify", "--strict", dmg)
    run("/usr/bin/xcrun", "stapler", "validate", dmg)
    run("/usr/sbin/spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg)
    run("/usr/bin/hdiutil", "verify", dmg)
    with tempfile.TemporaryDirectory(prefix="jerd-release-mount-") as temp:
        mount = pathlib.Path(temp)
        mounted = False
        try:
            run("/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mount, dmg)
            mounted = True
            installed = mount / "Jerd.app"
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", installed)
            run("/usr/bin/xcrun", "stapler", "validate", installed)
            run("/usr/sbin/spctl", "--assess", "--type", "execute", installed)
            mounted_info = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
            if mounted_info != info or any(digest(installed / name) != digest(app / name) for name in [
                "Contents/MacOS/Jerd", "Contents/_CodeSignature/CodeResources"]):
                raise ValueError("The DMG contains a different app")
        finally:
            if mounted:
                run("/usr/bin/hdiutil", "detach", mount)
    print("Release signatures, notarization, runtime receipts, symbols, and feed passed.", flush=True)
    return manifest
