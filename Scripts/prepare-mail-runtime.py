#!/usr/bin/env python3
"""Prepare the fixed upstream Mailpit binary without installing a system service."""
import hashlib
import json
import os
import pathlib
import platform
import shutil
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
PIN = json.loads((ROOT / "MailRuntime/pin.json").read_text())
DESTINATION = ROOT / ".build/mail-runtime"
HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"}


def validate_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in HOSTS:
        raise RuntimeError("Unexpected Mailpit download URL")


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
        raise RuntimeError("This development Mailpit payload requires an arm64 Mac")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    target = DESTINATION / PIN["id"]
    if target.exists():
        receipt = json.loads((target / "receipt.json").read_text())
        if receipt["archiveSHA256"] != PIN["sha256"] or set(receipt["files"]) != {"mailpit", "LICENSE", "README.md"}:
            raise RuntimeError("The Mailpit receipt does not match its pin")
        for name, sha in receipt["files"].items():
            if (target / name).is_symlink() or digest(target / name) != sha:
                raise RuntimeError("The prepared Mailpit runtime changed: " + name)
    else:
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=DESTINATION) as temporary:
            stage = pathlib.Path(temporary)
            archive = stage / "mailpit.tar.gz"
            validate_url(PIN["url"])
            request = urllib.request.Request(PIN["url"], headers={"User-Agent": "Jerd-development-bootstrap"})
            opener = urllib.request.build_opener(HTTPSOnly())
            with opener.open(request, timeout=45) as response, archive.open("wb") as output:
                size = 0
                while block := response.read(1024 * 1024):
                    size += len(block)
                    if size > PIN["size"]:
                        raise RuntimeError("Mailpit download exceeds its size limit")
                    output.write(block)
            if archive.stat().st_size != PIN["size"] or digest(archive) != PIN["sha256"]:
                raise RuntimeError("Mailpit download integrity check failed")
            payload = stage / "payload"
            payload.mkdir(mode=0o700)
            files = {}
            with tarfile.open(archive) as source:
                for name in ("mailpit", "LICENSE", "README.md"):
                    member = source.getmember(name)
                    if not member.isfile() or member.size > 64 * 1024 * 1024:
                        raise RuntimeError("Invalid Mailpit archive member")
                    file = payload / name
                    with source.extractfile(member) as input_file, file.open("wb") as output:
                        shutil.copyfileobj(input_file, output)
                    file.chmod(0o700 if name == "mailpit" else 0o600)
                    files[name] = digest(file)
            receipt = {"schemaVersion": 1, "archiveSHA256": PIN["sha256"], "files": files}
            (payload / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            os.rename(payload, target)
    shutil.copyfile(ROOT / "MailRuntime/pin.json", DESTINATION / "pin.json")
    print("Prepared and verified Mailpit " + PIN["version"])


if __name__ == "__main__":
    main()
