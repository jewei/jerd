#!/usr/bin/env python3
"""Copy the verified development payload into a build; never downloads anything."""
import hashlib
import json
import pathlib
import shutil
import sys

root = pathlib.Path(__file__).resolve().parents[2]
source = root / ".build/development-runtimes"
destination = pathlib.Path(sys.argv[1])
pins = json.loads((root / "Runtimes/Development/pins.json").read_text())
if not all((source / entry["name"] / "jerd-receipt.json").is_file() for entry in pins["artifacts"]):
    if destination.exists():
        shutil.rmtree(destination)
    print("No prepared development payload. The app will require explicit local runtime selection.")
    sys.exit(0)
for entry in pins["artifacts"]:
    folder = source / entry["name"]
    receipt = json.loads((folder / "jerd-receipt.json").read_text())
    if receipt["archiveSHA256"] != entry["sha256"]:
        raise RuntimeError("The prepared runtime no longer matches its pin")
    if entry.get("format") == "composer-project":
        if receipt["fileSHA256"].get("composer.lock") != entry["sha256"]:
            raise RuntimeError("The Laravel installer lock file changed")
    elif set(receipt["fileSHA256"]) != set(entry["files"]):
        raise RuntimeError("The runtime file list changed")
    for name, digest in receipt["fileSHA256"].items():
        if pathlib.PurePosixPath(name).is_absolute() or ".." in pathlib.PurePosixPath(name).parts:
            raise RuntimeError("The payload has an invalid path")
        if hashlib.sha256((folder / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("The prepared runtime file changed: " + name)
destination.mkdir(parents=True, exist_ok=True)
for entry in pins["artifacts"]:
    target = destination / entry["name"]
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source / entry["name"], target)
shutil.copyfile(root / "Runtimes/Development/pins.json", destination / "pins.json")
print("Embedded the verified arm64 development payload and license notices.")
