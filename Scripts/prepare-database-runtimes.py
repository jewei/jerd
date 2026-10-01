#!/usr/bin/env python3
"""Prepare native development database runtimes. No system service is installed."""
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOWNLOADS = ROOT / ".build/database-downloads"
DESTINATION = ROOT / ".build/database-runtimes"
HOSTS = {"cdn.mysql.com", "repo.mysql.com", "github.com", "api.github.com",
         "raw.githubusercontent.com", "release-assets.githubusercontent.com",
         "objects.githubusercontent.com", "download.redis.io"}


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def validate_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in HOSTS:
        raise RuntimeError("Unexpected download URL")


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def download(url, name, expected, limit):
    validate_url(url)
    target = DOWNLOADS / name
    if target.exists():
        if digest(target) != expected:
            raise RuntimeError("The cached download changed: " + name)
        return target
    temporary = target.with_name(name + ".part")
    opener = urllib.request.build_opener(HTTPSOnly())
    print("Downloading " + name, flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "Jerd-development-bootstrap"})
    with opener.open(request, timeout=45) as response, temporary.open("wb") as output:
        count = 0
        while block := response.read(1024 * 1024):
            count += len(block)
            if count > limit:
                raise RuntimeError("Download exceeds its size limit")
            output.write(block)
    if digest(temporary) != expected:
        raise RuntimeError("Download integrity check failed: " + name)
    os.rename(temporary, target)
    return target


def safe_name(name):
    path = pathlib.PurePosixPath(name)
    if path.is_absolute() or not path.parts or ".." in path.parts:
        raise RuntimeError("Unsafe archive member")
    return path


def extract_tar(archive, destination, selected=lambda name: True):
    # Materialize safe in-archive links as regular files. The staged payload has
    # no symlink traversal or dependency on a different application directory.
    with tarfile.open(archive) as source:
        members = source.getmembers()
        roots = {safe_name(m.name).parts[0] for m in members}
        if len(roots) != 1:
            raise RuntimeError("Expected one archive root")
        for member in members:
            path = safe_name(member.name)
            if member.issym() or member.islnk():
                link = pathlib.PurePosixPath(member.linkname)
                resolved = (path.parent / link) if member.issym() else link
                normalized = pathlib.PurePosixPath(os.path.normpath(str(resolved)))
                if link.is_absolute() or normalized.parts[0] not in roots or ".." in normalized.parts:
                    raise RuntimeError("Archive link leaves its root")
            if len(path.parts) == 1:
                continue
            relative = pathlib.PurePosixPath(*path.parts[1:])
            if not selected(relative.as_posix()) or member.isdir():
                continue
            if not (member.isfile() or member.issym() or member.islnk()):
                raise RuntimeError("Unsupported archive member")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.extractfile(member) as input_file, target.open("wb") as output:
                shutil.copyfileobj(input_file, output)
            target.chmod(0o700 if member.mode & 0o111 else 0o600)


def verify_mysql(pin, archive, scratch):
    gpg = shutil.which("gpg")
    if not gpg:
        raise RuntimeError("GnuPG is required to verify the MySQL publisher signature")
    signature = download(pin["signatureURL"], pin["archive"] + ".asc", pin["signatureSHA256"], 16_384)
    key = download(pin["signingKeyURL"], "RPM-GPG-KEY-mysql-2025", pin["signingKeySHA256"], 32_768)
    home = scratch / "gnupg"
    home.mkdir(mode=0o700)
    command = [gpg, "--homedir", str(home), "--batch", "--no-options"]
    subprocess.run(command + ["--import", str(key)], check=True, capture_output=True)
    result = subprocess.run(command + ["--status-fd", "1", "--verify", str(signature), str(archive)],
                            check=True, capture_output=True, text=True)
    if "[GNUPG:] VALIDSIG " + pin["signingKeyFingerprint"] + " " not in result.stdout:
        raise RuntimeError("Unexpected MySQL signing key")


def prepare(pin, archive, scratch, payload):
    if pin["engine"] == "mysql":
        verify_mysql(pin, archive, scratch)
        bins = {"bin/mysqld", "bin/mysql", "bin/mysqladmin", "bin/mysqldump"}
        extract_tar(archive, payload, lambda name: name in bins or name in {"LICENSE", "README"}
                    or (name.startswith("bin/") and name.endswith(".dylib"))
                    or name.startswith("share/") or (name.startswith("lib/") and not name.endswith(".a")))
    elif pin["engine"] == "postgresql":
        mount = scratch / "volume"
        subprocess.run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(archive)],
                       check=True, stdout=subprocess.DEVNULL)
        try:
            app = mount / "Postgres.app"
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            version = app / "Contents/Versions/18"
            for name in ["bin", "lib", "share"]:
                for folder, dirs, files in os.walk(version / name, followlinks=True):
                    folder = pathlib.Path(folder)
                    if not folder.resolve().is_relative_to(version.resolve()):
                        raise RuntimeError("PostgreSQL directory link leaves its runtime")
                    for file in files:
                        source = folder / file
                        if not source.resolve().is_relative_to(version.resolve()):
                            raise RuntimeError("PostgreSQL file link leaves its runtime")
                        if source.suffix == ".a":
                            continue
                        target = payload / source.relative_to(version)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source, target, follow_symlinks=True)
            shutil.copy2(app / "Contents/Resources/Credits.rtf", payload / "PostgresApp-Credits.rtf")
        finally:
            subprocess.run(["/usr/bin/hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
    else:
        source = scratch / "redis-source"
        source.mkdir()
        extract_tar(archive, source)
        # The core Redis server has no external build dependency. Do not install
        # it into /usr/local, use Homebrew, or build optional module bundles.
        environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(scratch),
                           GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
                           SOURCE_DATE_EPOCH="1789603200")
        subprocess.run(["/usr/bin/make", "-j4", "MALLOC=libc", "BUILD_TLS=no", "redis-server", "redis-cli"],
                       cwd=source / "src", env=environment, check=True)
        (payload / "bin").mkdir()
        for name in ["redis-server", "redis-cli"]:
            shutil.copy2(source / "src" / name, payload / "bin" / name)
        for name in ["COPYING", "LICENSE.txt", "REDISCONTRIBUTIONS.txt"]:
            if (source / name).is_file():
                shutil.copy2(source / name, payload / name)
        shutil.copytree(source / "deps", payload / "build-dependency-notices",
                        ignore=shutil.ignore_patterns("*.o", "*.a", "*.so", "*.dylib"))


def main():
    pins = json.loads((ROOT / "DatabaseRuntimes/pins.json").read_text())
    if platform.system() != "Darwin" or platform.machine() != pins["architecture"]:
        raise RuntimeError("This development bootstrap requires an arm64 Mac")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for pin in pins["artifacts"]:
        target = DESTINATION / pin["id"]
        if target.exists():
            receipt = json.loads((target / "jerd-receipt.json").read_text())
            if receipt["archiveSHA256"] != pin["sha256"]:
                raise RuntimeError("The prepared database runtime uses a different pin")
            for name, record in receipt["files"].items():
                safe_name(name)
                if digest(target / name) != record["sha256"]:
                    raise RuntimeError("The prepared runtime changed: " + name)
            print("Verified " + pin["id"], flush=True)
            continue
        archive = download(pin["url"], pin["archive"], pin["sha256"], pin["size"])
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=DESTINATION) as temporary:
            scratch = pathlib.Path(temporary)
            payload = scratch / "payload"
            payload.mkdir(mode=0o700)
            prepare(pin, archive, scratch, payload)
            files = {}
            for path in payload.rglob("*"):
                if path.is_symlink():
                    raise RuntimeError("The staged runtime contains a symbolic link")
                if path.is_file():
                    executable = bool(path.stat().st_mode & 0o111)
                    files[path.relative_to(payload).as_posix()] = {"sha256": digest(path), "executable": executable}
                    path.chmod(0o700 if executable else 0o600)
            receipt = {"schemaVersion": 1, "archiveSHA256": pin["sha256"], "files": files}
            (payload / "jerd-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            os.rename(payload, target)
        print("Prepared " + pin["id"], flush=True)
    shutil.copyfile(ROOT / "DatabaseRuntimes/pins.json", DESTINATION / "pins.json")


if __name__ == "__main__":
    main()
