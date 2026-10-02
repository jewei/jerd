#!/usr/bin/env python3
"""Prepare, validate, or publish a signed Jerd release from this Mac."""
import argparse
import datetime
import email.utils
import json
import os
import pathlib
import plistlib
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET

from release_common import (FEED_URL, REPOSITORY, ROOT, SPARKLE, SPARKLE_ACCOUNT,
                            digest, require_clean_source, run, version_tuple, write_json)
from release_runtimes import sign_payloads
from release_support import prepare as prepare_support
from release_validation import validate, verify_app, verify_symbols, verify_sparkle_key

NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NAMESPACE)


def release_versions(version, build, feed, project):
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+){0,2}", version) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("Use a numeric release version and a positive integer build.")
    tree = ET.fromstring(feed)
    channel = tree.find("channel")
    if tree.tag != "rss" or channel is None:
        raise ValueError("The existing appcast is invalid.")
    current = re.search(r'CURRENT_PROJECT_VERSION: "(\d+)"', project)
    if not current or int(build) <= int(current.group(1)):
        raise ValueError("The build must exceed CURRENT_PROJECT_VERSION.")
    for item in channel.findall("item"):
        old_build = item.findtext("{" + NAMESPACE + "}version", "")
        old_version = item.findtext("{" + NAMESPACE + "}shortVersionString", "")
        if not old_build.isdigit() or int(build) <= int(old_build):
            raise ValueError("The build must exceed every published build.")
        if version_tuple(version) <= version_tuple(old_version):
            raise ValueError("The version must exceed every published version.")
    return tree


def release_notes(changelog):
    match = re.search(r"^## \[Unreleased\]\s*\n(.*?)(?=^## \[|\Z)", changelog, re.M | re.S)
    if not match or not match.group(1).strip():
        raise ValueError("Add release notes to CHANGELOG.md under [Unreleased].")
    return match.group(1).strip() + "\n"


def make_feed(base, destination, archive, version, build, minimum, notes):
    tree = ET.fromstring(base)
    channel = tree.find("channel")
    if channel is None:
        raise ValueError("The appcast has no channel.")
    item = ET.Element("item")
    for key, value in [("title", "Jerd " + version), ("pubDate", email.utils.formatdate(usegmt=True)),
                       ("{" + NAMESPACE + "}version", build),
                       ("{" + NAMESPACE + "}shortVersionString", version),
                       ("{" + NAMESPACE + "}minimumSystemVersion", minimum),
                       ("{" + NAMESPACE + "}hardwareRequirements", "arm64"), ("description", notes)]:
        ET.SubElement(item, key).text = value
    signature = run(SPARKLE / "sign_update", "--account", SPARKLE_ACCOUNT, "-p", archive)
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/{REPOSITORY}/releases/download/v{version}/{archive.name}",
        "length": str(archive.stat().st_size), "type": "application/octet-stream",
        "{" + NAMESPACE + "}edSignature": signature})
    channel.insert(0, item)
    ET.ElementTree(tree).write(destination, encoding="utf-8", xml_declaration=True)
    run(SPARKLE / "sign_update", "--account", SPARKLE_ACCOUNT, destination)


def notary(path, options, directory, name):
    auth = ["--keychain-profile", options.keychain_profile]
    if options.keychain:
        auth += ["--keychain", str(options.keychain)]
    print("Submit " + name + " to Apple. This can take several minutes.", flush=True)
    output = run("/usr/bin/xcrun", "notarytool", "submit", path, *auth, "--wait", "--timeout", "45m",
                 "--output-format", "json", log=directory / (name + "-notary.log"), timeout=3000)
    record = json.loads(output)
    write_json(directory / (name + "-notary.json"), record)
    if record.get("status") != "Accepted":
        if record.get("id"):
            run("/usr/bin/xcrun", "notarytool", "log", record["id"], *auth,
                directory / (name + "-notary-issues.json"))
        raise RuntimeError("Apple did not accept " + name + ". See the retained notary logs.")
    return record["id"]


def test_runtimes(app, directory):
    resources = app / "Contents/Resources"
    database = resources / "DatabaseRuntimes"
    mail = json.loads((resources / "MailRuntime/pin.json").read_text())["id"]
    storage = json.loads((resources / "StorageRuntime/pin.json").read_text())["id"]
    environment = {key: value for key, value in os.environ.items() if not key.startswith("JERD_")}
    environment.update({
        "JERD_INTEGRATION": "1", "JERD_DATABASE_INTEGRATION": "1", "JERD_MAIL_INTEGRATION": "1",
        "JERD_STORAGE_INTEGRATION": "1", "JERD_RELEASE_RESOURCES": str(resources),
        "JERD_PHP_CLI": str(resources / "DevelopmentRuntimes/php/php-native-8.5"),
        "JERD_PHP_FPM": str(resources / "DevelopmentRuntimes/php/php-native-fpm-8.5"),
        "JERD_CADDY": str(resources / "DevelopmentRuntimes/caddy/caddy"),
        "JERD_DATABASE_RUNTIMES": str(database),
        "JERD_MAIL_RUNTIME": str(resources / "MailRuntime" / mail),
        "JERD_STORAGE_RUNTIME": str(resources / "StorageRuntime" / storage)})
    print("Test signed runtimes with private data and loopback ports.", flush=True)
    # Tests own data services. Let their bounded service controls perform shutdown;
    # do not kill the parent test runner with an outer timeout.
    run("/usr/bin/swift", "test", "--package-path", ROOT / "Packages/JerdCore", env=environment,
        cwd=ROOT, log=directory / "runtime-tests.log", timeout=None)


def sign_sparkle(app, identity):
    # Archive signing does not replace the ad hoc signatures on Sparkle's tools.
    # Follow Sparkle's documented manual signing order before sealing the app.
    framework = app / "Contents/Frameworks/Sparkle.framework"
    for name in ["Versions/B/XPCServices/Installer.xpc", "Versions/B/XPCServices/Downloader.xpc",
                 "Versions/B/Autoupdate", "Versions/B/Updater.app", "."]:
        options = ["--preserve-metadata=entitlements"] if name.endswith("Downloader.xpc") else []
        run("/usr/bin/codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp",
            *options, framework / name)


def prepare(options):
    source = require_clean_source()
    feed = (ROOT / "appcast.xml").read_bytes()
    release_versions(options.version, options.build, feed, (ROOT / "project.yml").read_text())
    notes = release_notes((ROOT / "CHANGELOG.md").read_text())
    minimum = options.minimum_macos or run("/usr/bin/sw_vers", "-productVersion")
    version_tuple(minimum)
    if not re.fullmatch(r"[A-Z0-9]{10}", options.team):
        raise ValueError("Invalid signing team.")
    identity = options.identity or f"Developer ID Application: Jewei Mak ({options.team})"
    # Check credentials and the existing signed feed before a lengthy build.
    verify_sparkle_key()
    run(SPARKLE / "sign_update", "--account", SPARKLE_ACCOUNT, "--verify", ROOT / "appcast.xml")
    auth = ["--keychain-profile", options.keychain_profile]
    if options.keychain:
        auth += ["--keychain", str(options.keychain)]
    run("/usr/bin/xcrun", "notarytool", "history", *auth, "--output-format", "json")
    releases = ROOT / ".build/releases"
    releases.mkdir(parents=True, exist_ok=True)
    directory = pathlib.Path(tempfile.mkdtemp(prefix=f"Jerd-{options.version}-{options.build}-", dir=releases))
    directory.chmod(0o700)
    print("Prepare private candidate: " + str(directory), flush=True)
    (directory / "source-appcast.xml").write_bytes(feed)
    (directory / "release-notes.md").write_text(notes + f"\nRequires Apple Silicon and macOS {minimum} or later.\n")
    archive = directory / "Jerd.xcarchive"
    print("Archive the Release app.", flush=True)
    run("/usr/bin/xcodebuild", "archive", "-project", ROOT / "Jerd.xcodeproj", "-scheme", "Jerd",
        "-configuration", "Release", "-destination", "generic/platform=macOS", "-archivePath", archive,
        "-derivedDataPath", directory / "DerivedData", "-clonedSourcePackagesDirPath", ROOT / ".build/SourcePackages",
        "-disableAutomaticPackageResolution", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_IDENTITY=" + identity, "DEVELOPMENT_TEAM=" + options.team,
        "MARKETING_VERSION=" + options.version, "CURRENT_PROJECT_VERSION=" + options.build,
        cwd=ROOT, log=directory / "archive.log", timeout=1800)
    # The archive already uses Developer ID. Copy its app before changing runtime payloads.
    app = directory / "export/Jerd.app"
    app.parent.mkdir()
    run("/usr/bin/ditto", archive / "Products/Applications/Jerd.app", app, timeout=300)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["LSMinimumSystemVersion"] = minimum
    info_path.write_bytes(plistlib.dumps(info))
    support = directory / "support"
    prepare_support(support)
    print("Sign the bundled runtime files.", flush=True)
    report = sign_payloads(app, identity, options.team, support)
    write_json(directory / "runtime-signing.json", report)
    sign_sparkle(app, identity)
    for path in [app / "Contents/MacOS/JerdCLI", app / "Contents/Library/LaunchServices/JerdHelper", app]:
        run("/usr/bin/codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp", path)
    verify_app(app, options.team, minimum, notarized=False)
    symbols = directory / "symbols"
    run("/usr/bin/ditto", archive / "dSYMs", symbols)
    verify_symbols(app, symbols)
    symbols_zip = directory / f"Jerd-{options.version}-{options.build}.dSYMs.zip"
    run("/usr/bin/ditto", "-c", "-k", "--keepParent", symbols, symbols_zip)
    test_runtimes(app, directory)
    require_clean_source(source)
    submission = directory / "notary-app.zip"
    run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, submission, timeout=600)
    app_submission = notary(submission, options, directory, "app")
    run("/usr/bin/xcrun", "stapler", "staple", app)
    dmg_root = directory / "disk-image"
    dmg_root.mkdir()
    run("/usr/bin/ditto", app, dmg_root / "Jerd.app")
    (dmg_root / "Applications").symlink_to("/Applications")
    dmg = directory / f"Jerd-{options.version}.dmg"
    print("Create and notarize the disk image.", flush=True)
    run("/usr/bin/hdiutil", "create", "-volname", "Jerd", "-srcfolder", dmg_root,
        "-format", "UDZO", dmg, timeout=600)
    run("/usr/bin/codesign", "--sign", identity, "--timestamp", dmg)
    dmg_submission = notary(dmg, options, directory, "dmg")
    run("/usr/bin/xcrun", "stapler", "staple", dmg)
    make_feed(feed, directory / "appcast.xml", dmg, options.version, options.build, minimum, notes)
    require_clean_source(source)
    files = [dmg, symbols_zip, directory / "appcast.xml", directory / "release-notes.md"]
    write_json(directory / "release.json", {
        "schemaVersion": 1, "version": options.version, "build": options.build, "teamID": options.team,
        "minimumMacOS": minimum, "repository": REPOSITORY, "sourceCommit": source,
        "sourceFeedSHA256": digest(directory / "source-appcast.xml"), "dmg": dmg.name,
        "symbols": symbols_zip.name, "files": {path.name: digest(path) for path in files},
        "notarization": {"app": app_submission, "dmg": dmg_submission},
        "testedSystem": run("/usr/bin/sw_vers", "-productVersion"), "architecture": "arm64"})
    validate(directory)
    print("Private candidate ready: " + str(directory), flush=True)
    return directory


def promote_source(checkout, manifest, directory):
    version, build = manifest["version"], manifest["build"]
    project = checkout / "project.yml"
    text = project.read_text()
    for key, value in [("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", build)]:
        text, count = re.subn(r'(' + key + r': )"[^"\n]+"', lambda m: m[1] + '"' + value + '"', text)
        if count != 1:
            raise ValueError("Unexpected project version setting: " + key)
    project.write_text(text)
    pbx = checkout / "Jerd.xcodeproj/project.pbxproj"
    text = pbx.read_text()
    for key, value in [("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", build)]:
        text, count = re.subn(r'(' + key + r' = )[^;\n]+;', lambda m: m[1] + value + ";", text)
        if count != 2:
            raise ValueError("Unexpected generated project version setting: " + key)
    pbx.write_text(text)
    changelog = checkout / "CHANGELOG.md"
    text = changelog.read_text().replace("## [Unreleased]", "## [Unreleased]\n\n## [" + version + "] - " +
                                       datetime.datetime.now(datetime.timezone.utc).date().isoformat(), 1)
    changelog.write_text(text)
    shutil.copyfile(directory / "appcast.xml", checkout / "appcast.xml")


def publish(options):
    directory = options.directory.resolve()
    manifest = validate(directory)
    require_clean_source(manifest["sourceCommit"])
    if (directory / "publication.json").exists():
        raise RuntimeError("Publication has already started. Inspect publication.json and recover manually.")
    origin = run("git", "remote", "get-url", "origin", cwd=ROOT)
    if origin not in [f"git@github.com:{REPOSITORY}.git", f"https://github.com/{REPOSITORY}.git", f"https://github.com/{REPOSITORY}"]:
        raise ValueError("Origin does not match " + REPOSITORY)
    run("git", "fetch", "origin", "main", cwd=ROOT)
    if run("git", "rev-parse", "FETCH_HEAD", cwd=ROOT) != manifest["sourceCommit"]:
        raise ValueError("The candidate source must equal origin/main. Prepare a new candidate after source changes.")
    if digest(ROOT / "appcast.xml") != manifest["sourceFeedSHA256"]:
        raise ValueError("The public feed changed after preparation.")
    release_versions(manifest["version"], manifest["build"], (ROOT / "appcast.xml").read_bytes(),
                     (ROOT / "project.yml").read_text())
    tag = "v" + manifest["version"]
    if json.loads(run("gh", "api", f"repos/{REPOSITORY}/git/matching-refs/tags/{tag}")):
        raise ValueError("This release tag already exists. Do not replace released assets.")
    # Keep the user's checkout clean. The staged commit includes the exact candidate feed.
    checkout = directory / "publication-worktree"
    run("git", "worktree", "add", "--detach", checkout, manifest["sourceCommit"], cwd=ROOT)
    promote_source(checkout, manifest, directory)
    run("git", "add", "project.yml", "Jerd.xcodeproj/project.pbxproj", "CHANGELOG.md", "appcast.xml", cwd=checkout)
    run("git", "commit", "-m", "Release " + tag, cwd=checkout)
    commit = run("git", "rev-parse", "HEAD", cwd=checkout)
    branch = "release-staging/" + tag
    state = {"commit": commit, "branch": branch, "tag": tag, "stage": "commit"}
    write_json(directory / "publication.json", state)
    run("git", "push", "origin", commit + ":refs/heads/" + branch, cwd=ROOT)
    run("gh", "release", "create", tag, directory / manifest["dmg"], directory / manifest["symbols"],
        "--repo", REPOSITORY, "--target", commit, "--title", "Jerd " + manifest["version"],
        "--notes-file", directory / "release-notes.md", "--draft", timeout=1800)
    state["stage"] = "draft"
    write_json(directory / "publication.json", state)
    downloads = directory / "published-assets"
    downloads.mkdir()
    run("gh", "release", "download", tag, "--repo", REPOSITORY, "--dir", downloads, timeout=1800)
    for name in [manifest["dmg"], manifest["symbols"]]:
        if digest(downloads / name) != manifest["files"][name]:
            raise ValueError("The uploaded asset differs from the candidate: " + name)
    run("gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false")
    state["stage"] = "assets-public"
    write_json(directory / "publication.json", state)
    # A normal fast-forward push refuses concurrent changes. Never force the public feed.
    run("git", "push", "origin", commit + ":refs/heads/main", cwd=ROOT)
    state["stage"] = "feed-public"
    write_json(directory / "publication.json", state)
    published_feed = run("gh", "api", "repos/" + REPOSITORY + "/contents/appcast.xml?ref=main",
                         "-H", "Accept: application/vnd.github.raw+json")
    if published_feed != (directory / "appcast.xml").read_text().strip():
        raise ValueError("The public feed differs from the signed candidate.")
    run("git", "push", "origin", "--delete", branch, cwd=ROOT)
    run("git", "worktree", "remove", checkout, cwd=ROOT)
    print("Published https://github.com/" + REPOSITORY + "/releases/tag/" + tag, flush=True)
    print("The local checkout remains on the source commit. Run git pull --ff-only to update it.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preparation = commands.add_parser("prepare", help="Build and verify a private candidate; do not publish.")
    preparation.add_argument("version")
    preparation.add_argument("build")
    preparation.add_argument("--team", default="4L4SS26L9J")
    preparation.add_argument("--identity")
    preparation.add_argument("--keychain-profile", default="notarytool")
    preparation.add_argument("--keychain", type=pathlib.Path, default=pathlib.Path.home() / "Library/Keychains/login.keychain-db")
    preparation.add_argument("--minimum-macos", help="Use only a macOS version covered by release testing; default: this Mac.")
    for name in ["validate", "publish"]:
        command = commands.add_parser(name)
        command.add_argument("directory", type=pathlib.Path)
    options = parser.parse_args()
    if options.command == "prepare":
        prepare(options)
    elif options.command == "validate":
        validate(options.directory)
    else:
        publish(options)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as error:
        sys.exit("Release stopped: " + str(error))
