"""CLI setup checks. All shell files and runtime fixtures are temporary."""
import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "Development/setup-php-cli.py"
SPEC = importlib.util.spec_from_file_location("cli_setup", SCRIPT)
cli_setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cli_setup)


class CLISetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="jerd cli café ")
        self.addCleanup(self.temp.cleanup)
        self.home = pathlib.Path(self.temp.name)
        self.app = self.home / "Library/Application Support/Jerd"
        self.bundle = self.home / "Jerd.app"
        launcher = self.bundle / "Contents/MacOS/JerdCLI"
        launcher.parent.mkdir(parents=True)
        launcher.write_bytes(b"test launcher")
        self.original = b"# User settings\nexport EDITOR=vi\n"
        (self.home / ".zshrc").write_bytes(self.original)
        self.install_runtime(updated=False)
        composer = self.app / "runtimes/composer/composer.phar"
        laravel = self.app / "runtime-updates/laravel/vendor/bin/laravel"
        for file in [composer, laravel]:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"companion fixture")
        (self.app / "runtimes/cli-tools.json").write_text(json.dumps({
            "composerPath": str(composer), "laravelPath": str(laravel),
            "composerVersion": "2.10.3", "laravelVersion": "5.32.0",
        }))

    def install_runtime(self, updated):
        build = self.app / ("runtime-updates/php-8.5-arm64-build" if updated else "runtimes/php-8.5-arm64")
        build.mkdir(parents=True, exist_ok=True)
        self.php = build / "php-native-8.5"
        self.php.write_bytes(b"trusted PHP fixture")
        hashes = {self.php.name: hashlib.sha256(self.php.read_bytes()).hexdigest()}
        receipt = {"schemaVersion": 1}
        if updated:
            receipt.update(kind="php", executable=self.php.name, files=hashes)
            name = "update-receipt.json"
        else:
            receipt["fileSHA256"] = hashes
            name = "jerd-receipt.json"
        (build / name).write_text(json.dumps(receipt))
        (self.app / "configuration.json").write_text(json.dumps({
            "defaultRuntimeID": "php-id", "runtimes": [{"id": "php-id", "cliPath": str(self.php)}],
        }))

    def setup_cli(self):
        with contextlib.redirect_stdout(io.StringIO()):
            cli_setup.setup(self.bundle, self.home)

    def test_versions_are_metadata_and_repeated_setup_keeps_one_block(self):
        for updated in [False, True]:
            with self.subTest(updated=updated):
                self.install_runtime(updated)
                self.setup_cli()
                first = (self.home / ".zshrc").read_bytes()
                self.setup_cli()
                self.assertEqual((self.home / ".zshrc").read_bytes(), first)
                self.assertTrue(first.startswith(self.original))
                for name in [".zprofile", ".zshrc"]:
                    self.assertEqual((self.home / name).read_text().count(cli_setup.START), 1)
                for name in ["php", "composer", "laravel"]:
                    self.assertEqual((self.app / "bin" / name).resolve(), (self.app / "bin/JerdCLI").resolve())
        backups = list((self.app / "shell-backups").glob("*/.zshrc"))
        self.assertTrue(any(file.read_bytes() == self.original for file in backups))

    def test_changed_runtime_cannot_change_shell_files(self):
        for updated in [False, True]:
            with self.subTest(updated=updated):
                self.install_runtime(updated)
                self.php.write_bytes(b"changed PHP fixture")
                with self.assertRaisesRegex(RuntimeError, "failed verification"):
                    self.setup_cli()
                self.assertEqual((self.home / ".zshrc").read_bytes(), self.original)
                self.assertFalse((self.home / ".zprofile").exists())

    def test_symbolic_shell_file_is_preserved_before_any_shell_change(self):
        target = self.home / "custom.zshrc"
        (self.home / ".zshrc").rename(target)
        (self.home / ".zshrc").symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "symbolic link"):
            self.setup_cli()
        self.assertEqual(target.read_bytes(), self.original)
        self.assertTrue((self.home / ".zshrc").is_symlink())
        self.assertFalse((self.home / ".zprofile").exists())


if __name__ == "__main__":
    unittest.main()
