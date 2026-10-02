#!/usr/bin/env python3
"""Test Sparkle with temporary signed apps, files, and a loopback feed."""
import argparse
import functools
import http.server
import os
import pathlib
import plistlib
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = ROOT / ".build/SourcePackages/artifacts/sparkle/Sparkle"
FRAMEWORK = SPARKLE / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def fixture_pids(results, executable):
    """Return live PIDs only when their executable matches this case's app."""
    events = results.read_text() if results.exists() else ""
    candidates = {int(line[4:]) for line in events.splitlines() if line.startswith("pid:")}
    live = []
    for pid in candidates:
        query = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True)
        if query.returncode == 0 and query.stdout.strip() == str(executable):
            live.append(pid)
    return live


def check_case(root, binary, key, public_key, identity, mode):
    case = root / mode
    case.mkdir()
    bundle_id = "dev.jerd.updater-test." + uuid.uuid4().hex
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(case)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base_url = "http://127.0.0.1:" + str(server.server_port)
    results = case / "events.txt"
    source_app = case / "new" / "Updater Test.app"
    old_app = case / "installed" / "Updater Test.app"
    executable = old_app / "Contents/MacOS/UpdaterTest"
    processes = []
    try:
        for version, app in [("1", old_app), ("2", source_app)]:
            macos = app / "Contents/MacOS"
            macos.mkdir(parents=True)
            shutil.copy2(binary, macos / "UpdaterTest")
            run("/usr/bin/ditto", str(FRAMEWORK), str(app / "Contents/Frameworks/Sparkle.framework"))
            info = {
                "CFBundleIdentifier": bundle_id, "CFBundleName": "Updater Test", "CFBundleExecutable": "UpdaterTest",
                "CFBundlePackageType": "APPL", "CFBundleVersion": version, "CFBundleShortVersionString": version + ".0",
                "LSMinimumSystemVersion": "14.0", "SUFeedURL": base_url + "/appcast.xml", "SUPublicEDKey": public_key,
                "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False, "SUEnableSystemProfiling": False,
                "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
                "SUSignedFeedFailureExpirationInterval": 0,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
                "TestResultPath": str(results), "TestRefuseFirstQuit": mode == "refused-quit",
            }
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            run("/usr/bin/codesign", "--force", "--deep", "--options", "runtime", "--sign", identity, str(app))
        archive = case / "update.zip"
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(source_app), str(archive))
        signature = run(str(SPARKLE / "bin/sign_update"), "--ed-key-file", str(key), "-p", str(archive))
        ET.register_namespace("sparkle", NS)
        feed = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(feed, "channel")
        ET.SubElement(channel, "title").text = "Jerd isolated updater test"
        if mode != "no-update":
            item = ET.SubElement(channel, "item")
            ET.SubElement(item, "title").text = "Updater Test 2.0"
            ET.SubElement(item, "{" + NS + "}version").text = "2"
            ET.SubElement(item, "{" + NS + "}shortVersionString").text = "2.0"
            ET.SubElement(item, "{" + NS + "}minimumSystemVersion").text = "14.0"
            ET.SubElement(item, "enclosure", {"url": base_url + "/update.zip", "length": str(archive.stat().st_size),
                                            "type": "application/octet-stream", "{" + NS + "}edSignature": signature})
        feed_path = case / "appcast.xml"
        ET.ElementTree(feed).write(feed_path, encoding="utf-8", xml_declaration=True)
        run(str(SPARKLE / "bin/sign_update"), "--ed-key-file", str(key), str(feed_path))
        if mode == "altered-feed":
            feed_path.write_bytes(feed_path.read_bytes().replace(b"Updater Test 2.0", b"Updater Test 9.0"))
        if mode == "altered-archive":
            with archive.open("r+b") as file:
                file.seek(100)
                value = file.read(1)
                file.seek(100)
                file.write(bytes([value[0] ^ 1]))
        # Launch only this test app. The fixture never loads Jerd settings or services.
        with (case / "process.log").open("w") as log:
            process = subprocess.Popen([str(executable)], stdout=log, stderr=log)
            processes.append(process)
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                events = results.read_text() if results.exists() else ""
                completed = "quit-approved:2" in events or "failed" in events or "no-update" in events
                if completed and process.poll() is not None and not fixture_pids(results, executable):
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError(mode + " timed out: " + events + "\n" + (case / "process.log").read_text()[-2000:])
        info = plistlib.loads((old_app / "Contents/Info.plist").read_bytes())
        if mode in ("success", "refused-quit"):
            assert info["CFBundleVersion"] == "2" and "updated" in events, events
            assert events.index("quit-approved:1") < events.index("launched:2"), events
            if mode == "refused-quit":
                assert "quit-refused" in events and "version-after-refusal:1" in events, events
        elif mode == "no-update":
            assert "no-update" in events and info["CFBundleVersion"] == "1", events
        else:
            assert "failed" in events and info["CFBundleVersion"] == "1" and "ready" not in events, events
            assert "error:SUSparkleErrorDomain:3002:" in events and "EdDSA signature does not match" in events, events
            if mode == "altered-feed":
                assert "error:SUSparkleErrorDomain:1000:" in events, events
                assert "found:" not in events, events
        print(mode + ": PASS", flush=True)
    finally:
        server.shutdown()
        server.server_close()
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
        for pid in fixture_pids(results, executable):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 5
        while fixture_pids(results, executable) and time.monotonic() < deadline:
            time.sleep(0.1)
        if fixture_pids(results, executable):
            raise RuntimeError("The owned updater fixture did not stop: " + str(executable))
        subprocess.run(["/usr/bin/defaults", "delete", bundle_id], capture_output=True)
        shutil.rmtree(pathlib.Path.home() / "Library/Caches" / bundle_id, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, help="An available Apple code-signing identity")
    args = parser.parse_args()
    if not FRAMEWORK.exists():
        parser.error("Resolve the Sparkle package into .build/SourcePackages first.")
    (ROOT / ".build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="app-update-test-", dir=ROOT / ".build") as temp:
        root = pathlib.Path(temp)
        binary = root / "UpdaterTest"
        run("/usr/bin/xcrun", "swiftc", "-swift-version", "6", "-F", str(FRAMEWORK.parent), "-framework", "Sparkle",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            str(ROOT / "Scripts/Fixtures/AppUpdateTest.swift"), "-o", str(binary))
        key = root / "test-key"
        public_key = run(str(binary), "generate-test-key", str(key), env={**os.environ, "DYLD_FRAMEWORK_PATH": str(FRAMEWORK.parent)})
        for mode in ["no-update", "altered-feed", "altered-archive", "success", "refused-quit"]:
            check_case(root, binary, key, public_key, args.identity, mode)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error))
