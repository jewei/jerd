"""Release failure checks. These tests do not sign, upload, or start services."""
import json
import pathlib
import sys
import tempfile
import unittest
import os
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "Release"))
import release
from release_common import local_dependency, parallel_each, regular_file, run

EMPTY_FEED = b'<rss><channel><title>Jerd</title></channel></rss>'
PROJECT = 'CURRENT_PROJECT_VERSION: "2"\n'


class ReleaseTests(unittest.TestCase):
    def test_runtime_checks_remove_inherited_update_settings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            app = root / "Jerd.app"
            for group in ["MailRuntime", "StorageRuntime"]:
                folder = app / "Contents/Resources" / group
                folder.mkdir(parents=True)
                (folder / "pin.json").write_text('{"id":"selected-runtime"}')
            inherited = {"JERD_UPDATE_INTEGRATION": "1", "JERD_UPDATE_INSTALL": "1",
                         "JERD_UPDATE_DESTINATION": "/outside-candidate", "JERD_SECOND_PHP_CLI": "/outside"}
            with patch.dict(os.environ, inherited), patch.object(release, "run") as command:
                release.test_runtimes(app, root)
            environment = command.call_args.kwargs["env"]
            self.assertFalse(set(inherited) & set(environment))
            self.assertEqual(environment["JERD_DATABASE_INTEGRATION"], "1")
            self.assertTrue(environment["JERD_PHP_CLI"].startswith(str(app)))
            self.assertIsNone(command.call_args.kwargs["timeout"])

    def test_signing_does_not_schedule_more_work_after_a_failure(self):
        seen = []
        def operation(value):
            seen.append(value)
            raise RuntimeError("timestamp unavailable")
        with self.assertRaises(RuntimeError):
            parallel_each(operation, range(1000))
        self.assertLessEqual(len(seen), 4)

    def test_timeout_keeps_command_output(self):
        with tempfile.TemporaryDirectory() as temp:
            log = pathlib.Path(temp) / "command.log"
            with self.assertRaises(RuntimeError):
                run(sys.executable, "-c", "import time; print('before timeout', flush=True); time.sleep(5)",
                    log=log, timeout=0.2)
            self.assertIn("before timeout", log.read_text())
            self.assertIn("timed out", log.read_text())

    def test_first_release_accepts_an_empty_feed(self):
        release.release_versions("0.1.0", "3", EMPTY_FEED, PROJECT)
        with self.assertRaises(ValueError):
            release.release_versions("0.1.0", "2", EMPTY_FEED, PROJECT)

    def test_all_prior_builds_and_versions_are_checked(self):
        feed = b'''<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><s:version>4</s:version><s:shortVersionString>0.2.0</s:shortVersionString></item>
        <item><s:version>9</s:version><s:shortVersionString>0.3.0</s:shortVersionString></item>
        </channel></rss>'''
        with self.assertRaises(ValueError):
            release.release_versions("0.4.0", "8", feed, PROJECT)
        with self.assertRaises(ValueError):
            release.release_versions("0.3.0", "10", feed, PROJECT)
        release.release_versions("0.4.0", "10", feed, PROJECT)

    def test_release_notes_do_not_include_an_old_release(self):
        self.assertEqual(release.release_notes("## [Unreleased]\n\nNew.\n\n## [0.0.1]\nOld."), "New.\n")
        with self.assertRaises(ValueError):
            release.release_notes("## [Unreleased]\n\n## [0.0.1]\nOld.")

    def test_payload_paths_reject_links_and_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "valid").write_text("data")
            (root / "link").symlink_to(root / "valid")
            self.assertEqual(regular_file(root, "valid"), root / "valid")
            for name in ["../outside", "/absolute", "link", "./valid", "valid/../valid"]:
                with self.assertRaises(ValueError):
                    regular_file(root, name)

    def test_only_relocation_can_resolve_bare_upstream_libraries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "lib").mkdir()
            library = root / "lib/libicu.dylib"
            library.write_bytes(b"test")
            binary = root / "server"
            self.assertEqual(local_dependency(binary, "libicu.dylib", root, relocate=True), library.resolve())
            with self.assertRaises(ValueError):
                local_dependency(binary, "libicu.dylib", root)
            with self.assertRaises(ValueError):
                local_dependency(binary, "/opt/homebrew/lib/libicu.dylib", root, relocate=True)

    def publication(self, failure=None):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            candidate = root / "candidate"
            candidate.mkdir()
            (root / "appcast.xml").write_bytes(EMPTY_FEED)
            (root / "project.yml").write_text(PROJECT)
            (candidate / "appcast.xml").write_text("signed feed\n")
            manifest = {"sourceCommit": "a" * 40, "sourceFeedSHA256": "hash", "version": "0.1.0", "build": "3",
                        "dmg": "Jerd-0.1.0.dmg", "symbols": "symbols.zip",
                        "files": {"Jerd-0.1.0.dmg": "hash", "symbols.zip": "hash"}}
            commands = []

            def run(*args, **kwargs):
                args = tuple(str(x) for x in args)
                commands.append(args)
                if args[:4] == ("git", "remote", "get-url", "origin"):
                    return "https://github.com/jewei/jerd.git"
                if args[:3] == ("git", "rev-parse", "FETCH_HEAD"):
                    return "a" * 40
                if args[:3] == ("git", "rev-parse", "HEAD"):
                    return "b" * 40
                if args[:2] == ("gh", "api"):
                    return "signed feed" if "contents/appcast" in args[2] else "[]"
                if args[:3] == ("gh", "release", "create") and failure == "upload":
                    raise RuntimeError("upload failed")
                return ""

            def digest(path):
                return "wrong" if failure == "download" and "published-assets" in str(path) else "hash"

            with patch.object(release, "ROOT", root), patch.object(release, "validate", return_value=manifest), \
                 patch.object(release, "require_clean_source"), patch.object(release, "run", side_effect=run), \
                 patch.object(release, "digest", side_effect=digest), patch.object(release, "promote_source"):
                options = type("Options", (), {"directory": candidate})()
                if failure:
                    with self.assertRaises((ValueError, RuntimeError)):
                        release.publish(options)
                else:
                    release.publish(options)
            return commands

    def test_failed_upload_cannot_publish_feed(self):
        for failure in ["upload", "download"]:
            commands = self.publication(failure)
            self.assertFalse(any(command[:3] == ("gh", "release", "edit") for command in commands))
            self.assertFalse(any(any(arg.endswith(":refs/heads/main") for arg in command) for command in commands))

    def test_assets_are_verified_and_public_before_feed_push(self):
        commands = self.publication()
        download = next(i for i, cmd in enumerate(commands) if cmd[:3] == ("gh", "release", "download"))
        public = next(i for i, cmd in enumerate(commands) if cmd[:3] == ("gh", "release", "edit"))
        feed = next(i for i, cmd in enumerate(commands) if any(arg.endswith(":refs/heads/main") for arg in cmd))
        self.assertLess(download, public)
        self.assertLess(public, feed)


if __name__ == "__main__":
    unittest.main()
