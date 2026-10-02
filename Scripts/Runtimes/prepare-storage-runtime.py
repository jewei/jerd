#!/usr/bin/env python3
"""Prepare the fixed upstream RustFS binary without installing a system service."""
import hashlib
import json
import os
import pathlib
import platform
import shutil
import zipfile
import tempfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
PIN = json.loads((ROOT / "Runtimes/Storage/pin.json").read_text())
DESTINATION = ROOT / ".build/storage-runtime"
HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "raw.githubusercontent.com"}


def validate_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in HOSTS:
        raise RuntimeError("Unexpected RustFS download URL")


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main():
    if platform.system() != "Darwin" or platform.machine() != PIN["architecture"]:
        raise RuntimeError("This development RustFS payload requires an arm64 Mac")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    target = DESTINATION / PIN["id"]
    if target.exists():
        receipt = json.loads((target / "receipt.json").read_text())
        if receipt["archiveSHA256"] != PIN["sha256"] or set(receipt["files"]) != {"rustfs", "LICENSE"}:
            raise RuntimeError("The RustFS receipt does not match its pin")
        for name, sha in receipt["files"].items():
            if (target / name).is_symlink() or digest(target / name) != sha:
                raise RuntimeError("The prepared RustFS runtime changed: " + name)
    else:
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=DESTINATION) as temporary:
            stage = pathlib.Path(temporary)
            archive = stage / "rustfs.zip"
            validate_url(PIN["url"])
            request = urllib.request.Request(PIN["url"], headers={"User-Agent": "Jerd-development-bootstrap"})
            opener = urllib.request.build_opener(HTTPSOnly())
            with opener.open(request, timeout=45) as response, archive.open("wb") as output:
                size = 0
                while block := response.read(1024 * 1024):
                    size += len(block)
                    if size > PIN["size"]:
                        raise RuntimeError("RustFS download exceeds its size limit")
                    output.write(block)
            if archive.stat().st_size != PIN["size"] or digest(archive) != PIN["sha256"]:
                raise RuntimeError("RustFS download integrity check failed")
            payload = stage / "payload"
            payload.mkdir(mode=0o700)
            files = {}
            with zipfile.ZipFile(archive) as source:
                member = source.getinfo("rustfs")
                if len(source.infolist()) != 1 or member.file_size > 320 * 1024 * 1024 or (member.external_attr >> 16) & 0o170000 != 0o100000:
                    raise RuntimeError("Invalid RustFS archive member")
                file = payload / "rustfs"
                with source.open(member) as input_file, file.open("wb") as output:
                    shutil.copyfileobj(input_file, output)
                file.chmod(0o700)
                files["rustfs"] = digest(file)
            validate_url(PIN["licenseURL"])
            with opener.open(PIN["licenseURL"], timeout=30) as response:
                license_data = response.read(32 * 1024)
            if hashlib.sha256(license_data).hexdigest() != PIN["licenseSHA256"]:
                raise RuntimeError("RustFS license integrity check failed")
            (payload / "LICENSE").write_bytes(license_data)
            (payload / "LICENSE").chmod(0o600)
            files["LICENSE"] = PIN["licenseSHA256"]
            receipt = {"schemaVersion": 1, "archiveSHA256": PIN["sha256"], "files": files}
            (payload / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            os.rename(payload, target)
    shutil.copyfile(ROOT / "Runtimes/Storage/pin.json", DESTINATION / "pin.json")
    print("Prepared and verified RustFS " + PIN["version"])


if __name__ == "__main__":
    main()
