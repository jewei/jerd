#!/usr/bin/env python3
"""Embed the prepared database payload. This build step never downloads files."""
import hashlib
import json
import pathlib
import shutil
import sys

root = pathlib.Path(__file__).resolve().parents[2]
source = root / ".build/database-runtimes"
destination = pathlib.Path(sys.argv[1])
pins = json.loads((root / "Runtimes/Database/pins.json").read_text())
if not all((source / entry["id"] / "jerd-receipt.json").is_file() for entry in pins["artifacts"]):
    if destination.exists():
        shutil.rmtree(destination)
    print("No prepared database runtime payload.")
    sys.exit(0)
for entry in pins["artifacts"]:
    folder = source / entry["id"]
    receipt = json.loads((folder / "jerd-receipt.json").read_text())
    if receipt["archiveSHA256"] != entry["sha256"]:
        raise RuntimeError("The database runtime no longer matches its pin")
    for name, record in receipt["files"].items():
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or (folder / name).is_symlink():
            raise RuntimeError("The database payload has an invalid path")
        digest = hashlib.sha256()
        with (folder / name).open("rb") as data:
            for block in iter(lambda: data.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != record["sha256"]:
            raise RuntimeError("The prepared database runtime changed: " + name)
destination.mkdir(parents=True, exist_ok=True)
for entry in pins["artifacts"]:
    target = destination / entry["id"]
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source / entry["id"], target)
shutil.copyfile(root / "Runtimes/Database/pins.json", destination / "pins.json")
print("Embedded verified MySQL, PostgreSQL, and Redis development runtimes.")
