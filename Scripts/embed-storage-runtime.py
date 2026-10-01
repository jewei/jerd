#!/usr/bin/env python3
"""Embed the verified RustFS payload. Never download during an app build."""
import hashlib
import json
import pathlib
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
pin = json.loads((root / "StorageRuntime/pin.json").read_text())
source = root / ".build/storage-runtime" / pin["id"]
destination = pathlib.Path(sys.argv[1])
if not (source / "receipt.json").is_file():
    if destination.exists():
        shutil.rmtree(destination)
    print("No prepared RustFS runtime payload.")
    sys.exit(0)
receipt = json.loads((source / "receipt.json").read_text())
if receipt["archiveSHA256"] != pin["sha256"] or set(receipt["files"]) != {"rustfs", "LICENSE"}:
    raise RuntimeError("The RustFS receipt does not match its pin")
for name, expected in receipt["files"].items():
    file = source / name
    if file.is_symlink() or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
        raise RuntimeError("The RustFS payload changed: " + name)
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)
shutil.copytree(source, destination / pin["id"])
shutil.copyfile(root / "StorageRuntime/pin.json", destination / "pin.json")
print("Embedded verified RustFS development runtime.")
