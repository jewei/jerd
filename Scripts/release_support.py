#!/usr/bin/env python3
"""Build the pinned XZ library in a private directory for the RustFS release payload."""
import argparse
import json
import os
import pathlib
import shutil
import tarfile
import tempfile
import urllib.parse
import urllib.request

from release_common import ROOT, digest, run, write_json


class ReleaseHTTPS(urllib.request.HTTPRedirectHandler):
    @staticmethod
    def validate(url):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname not in {"github.com", "release-assets.githubusercontent.com",
                                                                "objects.githubusercontent.com"} or parsed.username:
            raise ValueError("Unapproved XZ download host")

    def redirect_request(self, request, fp, code, message, headers, newurl):
        self.validate(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


def prepare(destination):
    pin = json.loads((ROOT / "Release/xz.json").read_text())
    destination = pathlib.Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    archive = destination / "source.tar.gz"
    ReleaseHTTPS.validate(pin["url"])
    opener = urllib.request.build_opener(ReleaseHTTPS())
    with opener.open(pin["url"], timeout=60) as source, archive.open("wb") as output:
        total = 0
        while block := source.read(1024 * 1024):
            total += len(block)
            if total > pin["size"]:
                raise ValueError("The XZ archive exceeded its pinned size")
            output.write(block)
    if total != pin["size"] or digest(archive) != pin["sha256"]:
        raise ValueError("The XZ download does not match its pin")
    source = destination / "source"
    source.mkdir()
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        if len(members) > 10000 or sum(x.size for x in members) > 100 * 1024 * 1024:
            raise ValueError("The XZ source exceeds its extraction bounds")
        seen = set()
        for member in members:
            name = pathlib.PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or len(name.parts) < 1 or name.parts[0] != "xz-" + pin["version"]:
                raise ValueError("Invalid XZ archive path")
            if name in seen:
                raise ValueError("Duplicate XZ archive path")
            seen.add(name)
            target = source / name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as input_file, target.open("wb") as output:
                    shutil.copyfileobj(input_file, output)
                target.chmod(0o700 if member.mode & 0o111 else 0o600)
            else:
                raise ValueError("The XZ source contains a link or special file")
    package = source / ("xz-" + pin["version"])
    prefix = destination / "install"
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"],
                   "TMPDIR": tempfile.gettempdir(), "MACOSX_DEPLOYMENT_TARGET": "14.0",
                   "CC": "/usr/bin/clang", "CFLAGS": "-O2 -arch arm64", "LDFLAGS": "-arch arm64"}
    log = destination / "build.log"
    run(package / "configure", "--prefix=" + str(prefix), "--disable-static", "--enable-shared",
        "--disable-xz", "--disable-xzdec", "--disable-lzmadec", "--disable-lzmainfo",
        "--disable-scripts", "--disable-doc", "--disable-nls", "--disable-dependency-tracking",
        cwd=package, env=environment, log=log)
    run("/usr/bin/make", "-j4", cwd=package, env=environment, log=log)
    run("/usr/bin/make", "install", cwd=package, env=environment, log=log)
    shutil.copyfile(prefix / "lib/liblzma.5.dylib", destination / "liblzma.5.dylib")
    license_file = package / "COPYING.0BSD"
    shutil.copyfile(license_file, destination / "XZ-LICENSE.txt")
    write_json(destination / "receipt.json", {"source": pin, "files": {
        name: digest(destination / name) for name in ["liblzma.5.dylib", "XZ-LICENSE.txt"]}})
    print("Built and recorded XZ " + pin["version"], flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=pathlib.Path)
    prepare(parser.parse_args().destination.resolve())
