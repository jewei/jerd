#!/usr/bin/env python3
"""Stage explicitly approved development binaries. Never installs a system service.

Trust basis: the selected upstream's GitHub release metadata, authenticated by
HTTPS, plus the reviewed, fixed digest in this repository. This does not claim a
publisher signature, build attestation, or production runtime support.
"""
import datetime
import hashlib
import json
import os
import pathlib
import platform
import shutil
import ssl
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DESTINATION = ROOT / ".build" / "development-runtimes"
TLS = ssl.create_default_context()


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        if parsed.scheme != "https" or parsed.hostname not in {
            "github.com", "api.github.com", "release-assets.githubusercontent.com",
            "objects.githubusercontent.com", "github-releases.githubusercontent.com",
            "getcomposer.org", "raw.githubusercontent.com"
        }:
            raise RuntimeError("Refused an unexpected download redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


OPENER = urllib.request.build_opener(HTTPSOnly(), urllib.request.HTTPSHandler(context=TLS))


def fetch(url):
    return OPENER.open(urllib.request.Request(url, headers={
        "User-Agent": "Jerd-development-bootstrap", "Accept": "application/vnd.github+json"
    }), timeout=45)


def prepare_composer(pin):
    final = DESTINATION / pin["name"]
    expected = {"composer.phar": pin["sha256"], "LICENSE": pin["licenseSHA256"]}
    if final.exists():
        for name, digest in expected.items():
            if hashlib.sha256((final / name).read_bytes()).hexdigest() != digest:
                raise RuntimeError(f"Composer file changed: {name}")
        print(f"Verified existing {final}", flush=True)
        return
    with fetch(pin["url"] + ".sha256sum") as response:
        if response.read(4096).decode().split()[0] != pin["sha256"]:
            raise RuntimeError("The published Composer checksum changed")
    with tempfile.TemporaryDirectory(prefix=".stage-", dir=DESTINATION) as scratch:
        payload = pathlib.Path(scratch) / "payload"
        payload.mkdir(mode=0o700)
        for name, url in [("composer.phar", pin["url"]), ("LICENSE", pin["licenseURL"])]:
            limit = pin["size"] if name == "composer.phar" else 32_768
            with fetch(url) as response:
                data = response.read(limit + 1)
            if len(data) > limit or hashlib.sha256(data).hexdigest() != expected[name]:
                raise RuntimeError(f"Composer integrity check failed: {name}")
            (payload / name).write_bytes(data)
            (payload / name).chmod(0o600)
        receipt = {"schemaVersion": 1, "tag": pin["tag"], "archiveSHA256": pin["sha256"],
            "fileSHA256": expected, "metadataURL": pin["url"] + ".sha256sum",
            "authentication": "Official Composer HTTPS download and reviewed digest pins",
            "publisherSignatureVerified": False}
        (payload / "jerd-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        (payload / "jerd-receipt.json").chmod(0o600)
        os.rename(payload, final)
    print(f"Verified and staged {final}", flush=True)


def prepare_laravel(pin):
    specification = ROOT / "DevelopmentRuntimes/laravel-installer"
    lock = (specification / "composer.lock").read_bytes()
    if hashlib.sha256(lock).hexdigest() != pin["sha256"]:
        raise RuntimeError("The Laravel installer lock file changed; review and repin it")
    final = DESTINATION / pin["name"]
    if final.exists():
        receipt = json.loads((final / "jerd-receipt.json").read_text())
        if receipt["archiveSHA256"] != pin["sha256"]:
            raise RuntimeError("The prepared Laravel installer uses a different lock file")
        for name, digest in receipt["fileSHA256"].items():
            if hashlib.sha256((final / name).read_bytes()).hexdigest() != digest:
                raise RuntimeError(f"The Laravel installer file changed: {name}")
        print(f"Verified existing {final}", flush=True)
        return
    with tempfile.TemporaryDirectory(prefix=".stage-", dir=DESTINATION) as scratch:
        scratch = pathlib.Path(scratch)
        payload = scratch / "payload"
        payload.mkdir(mode=0o700)
        for name in pin["files"]:
            shutil.copyfile(specification / name, payload / name)
        environment = dict(os.environ, COMPOSER_HOME=str(scratch / "composer-home"), PHP_INI_SCAN_DIR="")
        subprocess.run([str(DESTINATION / "php/php-native-8.5"), "-n",
            str(DESTINATION / "composer/composer.phar"), "install", "--no-dev", "--no-plugins",
            "--no-scripts", "--no-interaction", "--prefer-dist"], cwd=payload, env=environment, check=True)
        hashes = {}
        for path in payload.rglob("*"):
            if path.is_symlink():
                raise RuntimeError("The Laravel payload must not contain symbolic links")
            if path.is_file():
                hashes[path.relative_to(payload).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
                path.chmod(0o600)
        receipt = {"schemaVersion": 1, "tag": pin["tag"], "archiveSHA256": pin["sha256"],
            "fileSHA256": hashes, "authentication": "Composer lock references and verified HTTPS; plugins and scripts disabled",
            "publisherSignatureVerified": False}
        (payload / "jerd-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        (payload / "jerd-receipt.json").chmod(0o600)
        os.rename(payload, final)
    print(f"Verified and staged {final}", flush=True)


def main():
    pins = json.loads((ROOT / "DevelopmentRuntimes/pins.json").read_text())
    if platform.system() != "Darwin" or platform.machine() != pins["architecture"]:
        raise RuntimeError("These development pins are for native arm64 macOS only")
    DESTINATION.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(DESTINATION, 0o700)
    for pin in pins["artifacts"]:
        if pin.get("format") == "composer-project":
            prepare_laravel(pin)
            continue
        if pin.get("format") == "file":
            prepare_composer(pin)
            continue
        metadata_url = f'https://api.github.com/repos/{pin["repository"]}/releases/tags/{pin["tag"]}'
        with fetch(metadata_url) as response:
            release = json.load(response)
        asset = next(a for a in release["assets"] if a["name"] == pin["asset"])
        if asset["id"] != pin["assetID"] or asset.get("digest") != "sha256:" + pin["sha256"] or asset["size"] != pin["size"]:
            raise RuntimeError(f'{pin["name"]}: release metadata changed; review and repin before execution')
        expected_url = f'https://github.com/{pin["repository"]}/releases/download/{pin["tag"]}/{pin["asset"]}'
        if asset["browser_download_url"] != expected_url:
            raise RuntimeError("Release metadata contains an unexpected artifact URL")
        final = DESTINATION / pin["name"]
        if final.exists():
            receipt = json.loads((final / "jerd-receipt.json").read_text())
            if receipt["archiveSHA256"] != pin["sha256"]:
                raise RuntimeError(f"Refusing to replace an existing runtime: {final}")
            for name, digest in receipt["fileSHA256"].items():
                if hashlib.sha256((final / name).read_bytes()).hexdigest() != digest:
                    raise RuntimeError(f"Installed development file changed: {name}")
            print(f"Verified existing {final}", flush=True)
            continue
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=DESTINATION) as scratch:
            scratch = pathlib.Path(scratch)
            archive = scratch / "runtime.tar.gz"
            digest = hashlib.sha256()
            count = 0
            print(f'Downloading {pin["asset"]}', flush=True)
            with fetch(expected_url) as response, archive.open("wb") as output:
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    count += len(block)
                    if count > pin["size"]:
                        raise RuntimeError("Artifact exceeds its declared size")
                    digest.update(block)
                    output.write(block)
            if count != pin["size"] or digest.hexdigest() != pin["sha256"]:
                raise RuntimeError("Artifact integrity check failed")
            payload = scratch / "payload"
            payload.mkdir(mode=0o700)
            file_hashes = {}
            # Read named regular files only. Never extract paths, links, devices,
            # install scripts, or shared extension modules from the archive.
            with tarfile.open(archive, "r:gz") as source:
                for name in pin["files"]:
                    matches = [entry for entry in source.getmembers() if entry.name.removeprefix("./") == name]
                    if len(matches) != 1 or not matches[0].isfile() or matches[0].size > 400_000_000:
                        raise RuntimeError(f"Missing or unsafe archive member: {name}")
                    data = source.extractfile(matches[0]).read()
                    path = payload / name
                    path.write_bytes(data)
                    path.chmod(0o700 if name == "caddy" or name.startswith("php-native") else 0o600)
                    file_hashes[name] = hashlib.sha256(data).hexdigest()
            receipt = {
                "schemaVersion": 1, "repository": pin["repository"], "tag": pin["tag"],
                "assetID": pin["assetID"], "metadataURL": metadata_url,
                "archiveSHA256": pin["sha256"], "fileSHA256": file_hashes,
                "verifiedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "authentication": "GitHub release API over verified HTTPS and reviewed local digest pin",
                "publisherSignatureVerified": False
            }
            (payload / "jerd-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
            os.chmod(payload / "jerd-receipt.json", 0o600)
            os.rename(payload, final)
            print(f"Verified and staged {final}", flush=True)
    print("Staging complete. Composer used Jerd PHP to install the locked Laravel tool with plugins and scripts disabled.")


if __name__ == "__main__":
    main()
