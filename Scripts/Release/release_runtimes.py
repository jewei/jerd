#!/usr/bin/env python3
"""Sign copied runtime payloads, then record their new hashes and installation IDs."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

from release_common import ROOT, digest, identifier, is_macho, local_dependency, macho_details, parallel_each, regular_file, run, write_json

ALLOWED_ENTITLEMENTS = {"com.apple.security.cs.allow-jit", "com.apple.security.cs.allow-unsigned-executable-memory",
                        "com.apple.security.cs.disable-library-validation"}
PYTHON_EXTENSIONS = {"plpython3", "hstore_plpython3", "jsonb_plpython3", "ltree_plpython3"}


def payloads(resources):
    for group in ["DevelopmentRuntimes", "DatabaseRuntimes", "MailRuntime", "StorageRuntime"]:
        root = resources / group
        manifest_path = root / ("pins.json" if group.endswith("Runtimes") else "pin.json")
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("schemaVersion") != 1 or manifest.get("architecture") != "arm64":
            raise ValueError("Unsupported runtime manifest: " + group)
        entries = manifest.get("artifacts", [manifest])
        for entry in entries:
            name = identifier(entry.get("name", entry.get("id")))
            folder = root / name
            if folder.is_symlink() or not folder.is_dir():
                raise ValueError("Missing runtime folder: " + name)
            receipt_path = folder / ("jerd-receipt.json" if group.endswith("Runtimes") else "receipt.json")
            receipt = json.loads(receipt_path.read_text())
            if receipt.get("schemaVersion") != 1 or receipt.get("archiveSHA256") != entry.get("sha256"):
                raise ValueError("The runtime receipt does not match its pin: " + name)
            key = "fileSHA256" if group == "DevelopmentRuntimes" else "files"
            records = receipt[key]
            if not 0 < len(records) <= 20000:
                raise ValueError("Invalid runtime file count")
            listed = set(records) | {receipt_path.name}
            actual = set()
            for path in folder.rglob("*"):
                if path.is_symlink():
                    raise ValueError("Runtime payload contains a symbolic link")
                if path.is_file():
                    actual.add(path.relative_to(folder).as_posix())
            if listed != actual:
                raise ValueError("Unrecorded or missing runtime files: " + name)
            for name, record in records.items():
                expected = record["sha256"] if isinstance(record, dict) else record
                if digest(regular_file(folder, name)) != expected:
                    raise ValueError("Runtime digest mismatch: " + name)
            yield group, manifest_path, manifest, entry, folder, receipt_path, receipt, key


def add_xz(folder, receipt, support):
    record = json.loads((support / "receipt.json").read_text())
    if record["source"] != json.loads((ROOT / "Runtimes/Support/xz.json").read_text()):
        raise ValueError("The XZ source pin differs from the release pin")
    for name in ["liblzma.5.dylib", "XZ-LICENSE.txt"]:
        source = regular_file(support, name)
        if digest(source) != record["files"].get(name):
            raise ValueError("The built XZ library or license changed")
        shutil.copyfile(source, folder / name)
        (folder / name).chmod(0o600)
        receipt["files"][name] = digest(folder / name)
    receipt["additionalSources"] = {"xz": record["source"]}
    run("/usr/bin/install_name_tool", "-change", "/opt/homebrew/opt/xz/lib/liblzma.5.dylib",
        "@loader_path/liblzma.5.dylib", folder / "rustfs")


def omit_python_extensions(folder, receipt):
    """The upstream optional PL/Python modules require an external Python framework."""
    excluded = {}
    for name, record in list(receipt["files"].items()):
        path = pathlib.PurePosixPath(name)
        library = path.parent.as_posix() == "lib/postgresql" and path.stem in PYTHON_EXTENSIONS
        control = path.parent.as_posix() == "share/postgresql/extension" and any(
            path.name.startswith(prefix + "u.") or path.name.startswith(prefix + "u--")
            for prefix in PYTHON_EXTENSIONS)
        if library or control:
            regular_file(folder, name).unlink()
            excluded[name] = record["sha256"]
            del receipt["files"][name]
    receipt["excludedUpstreamFiles"] = excluded


def sign_binary(path, folder, identity, entitlements_directory):
    architectures = run("/usr/bin/lipo", "-archs", path).split()
    if "arm64" not in architectures:
        raise ValueError("A bundled binary has no arm64 slice: " + str(path))
    if architectures != ["arm64"]:
        temporary = path.with_name(path.name + ".arm64")
        run("/usr/bin/lipo", path, "-thin", "arm64", "-output", temporary)
        temporary.chmod(path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    info = macho_details(path)
    arguments = []
    for dependency in info["dependencies"]:
        target = local_dependency(path, dependency, folder, info["rpaths"], relocate=True)
        if target is not None:
            relative = "@loader_path/" + os.path.relpath(target, path.parent)
            if dependency != relative:
                arguments += ["-change", dependency, relative]
    if info["library"]:
        arguments += ["-id", "@rpath/" + path.name]
    if arguments:
        run("/usr/bin/install_name_tool", *arguments, path)
    # Keep only reviewed runtime entitlements. No debug or task-access entitlement survives.
    result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)], capture_output=True)
    entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
    if set(entitlements) - ALLOWED_ENTITLEMENTS or any(value is not True for value in entitlements.values()):
        raise ValueError("Unreviewed runtime entitlements: " + str(path))
    if path.name.startswith("php-native"):
        # PHP's PCRE and optional OPcache JIT allocate executable memory.
        entitlements.update({"com.apple.security.cs.allow-jit": True,
                             "com.apple.security.cs.allow-unsigned-executable-memory": True})
    signing = ["/usr/bin/codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity]
    if entitlements:
        entitlement_file = entitlements_directory / (hashlib.sha256(str(path).encode()).hexdigest() + ".plist")
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        signing += ["--entitlements", str(entitlement_file), "--generate-entitlement-der"]
    run(*signing, path)
    run("/usr/bin/codesign", "--verify", "--strict", path)
    return path


def sign_payloads(app, identity, team, support):
    resources = app / "Contents/Resources"
    # Complete receipt checks before any payload is modified.
    groups = list(payloads(resources))
    manifests = {}
    report = {"teamID": team, "architecture": "arm64", "payloads": []}
    with tempfile.TemporaryDirectory(prefix="jerd-entitlements-") as temporary:
        entitlement_directory = pathlib.Path(temporary)
        for group, manifest_path, manifest, entry, folder, receipt_path, receipt, key in groups:
            source_receipt = digest(receipt_path)
            if group == "StorageRuntime":
                add_xz(folder, receipt, support)
            if group == "DatabaseRuntimes" and entry["engine"] == "postgresql":
                omit_python_extensions(folder, receipt)
            binaries = [regular_file(folder, name) for name in receipt[key] if is_macho(regular_file(folder, name))]
            # Every task modifies one independent regular file; no nested bundles occur here.
            parallel_each(lambda path: sign_binary(path, folder, identity, entitlement_directory), binaries)
            for name, record in receipt[key].items():
                value = digest(regular_file(folder, name))
                if isinstance(record, dict):
                    record["sha256"] = value
                else:
                    receipt[key][name] = value
            fingerprint = hashlib.sha256(json.dumps(receipt[key], sort_keys=True).encode()).hexdigest()[:16]
            base = entry.get("id") or f"{entry['name']}-{entry['tag']}-arm64"
            entry["installationID"] = identifier(base + "-release-" + fingerprint)
            receipt["releaseSigning"] = {"teamID": team, "sourceReceiptSHA256": source_receipt}
            write_json(receipt_path, receipt)
            manifests[manifest_path] = manifest
            report["payloads"].append({"name": base, "installationID": entry["installationID"], "signedBinaries": len(binaries)})
            print(f"Signed {base}: {len(binaries)} binaries", flush=True)
    for path, manifest in manifests.items():
        write_json(path, manifest)
    # Re-read all receipts after signing. The outer app signature seals these manifests.
    list(payloads(resources))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--support", type=pathlib.Path, required=True)
    args = parser.parse_args()
    result = sign_payloads(args.app.resolve(), args.identity, args.team, args.support.resolve())
    write_json(args.app.parent / "runtime-signing.json", result)
