#!/usr/bin/env python3
"""Explicit, optional zsh setup for Jerd's project-aware CLI commands."""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import shutil

START = "# >>> Jerd PHP CLI >>>"
END = "# <<< Jerd PHP CLI <<<"
BLOCK = f'''{START}
export PATH="$HOME/Library/Application Support/Jerd/bin:$PATH"
{END}
'''


def verify_php(executable, app):
    executable = executable.resolve(strict=True)
    for name, receipt_name, hash_key in [
        ("runtimes", "jerd-receipt.json", "fileSHA256"),
        ("runtime-updates", "update-receipt.json", "files"),
    ]:
        root = (app / name).resolve()
        if not executable.is_relative_to(root):
            continue
        relative = executable.relative_to(root)
        if len(relative.parts) < 2:
            break
        build = root / relative.parts[0]
        receipt = json.loads((build / receipt_name).read_text())
        entry = executable.relative_to(build).as_posix()
        if receipt.get("schemaVersion") != 1:
            raise RuntimeError("The installed PHP receipt is not supported")
        if name == "runtime-updates" and (receipt.get("kind") != "php" or receipt.get("executable") != entry):
            raise RuntimeError("The installed PHP receipt does not match the selected executable")
        digest = hashlib.sha256()
        with executable.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != receipt.get(hash_key, {}).get(entry):
            raise RuntimeError("The installed PHP executable failed verification")
        return
    raise RuntimeError("Select a managed Jerd PHP runtime before setting up its CLI command")


def setup(app_bundle, home):
    app = home / "Library/Application Support/Jerd"
    config = json.loads((app / "configuration.json").read_text())
    runtime = next(r for r in config["runtimes"] if r["id"] == config["defaultRuntimeID"])
    executable = pathlib.Path(runtime["cliPath"])
    verify_php(executable, app)
    directory = app / "bin"
    if directory.is_symlink():
        raise RuntimeError("The CLI directory must not be a symbolic link")
    directory.mkdir(mode=0o700, exist_ok=True)
    source = app_bundle / "Contents/MacOS/JerdCLI"
    if not source.is_file():
        raise RuntimeError("Build or install a Jerd app with its CLI companion first")
    companions = json.loads((app / "runtimes/cli-tools.json").read_text())
    for key in ("composerPath", "laravelPath"):
        path = companions.get(key)
        if not isinstance(path, str) or not path or not pathlib.Path(path).is_file():
            raise RuntimeError("Open Jerd to install Composer and the Laravel installer first")
    commands = [directory / name for name in ("php", "composer", "laravel")]
    for command in commands:
        if command.exists() or command.is_symlink():
            owned_runtime = any(command.resolve().is_relative_to((app / name).resolve())
                                for name in ("runtimes", "runtime-updates"))
            if not command.is_symlink() or not (owned_runtime or command.resolve() == (directory / "JerdCLI").resolve()):
                raise RuntimeError(f"An unrelated {command.name} command already exists; it was not changed")

    # Check both files before changing either. Keep their exact prior bytes.
    updates = []
    for name in [".zprofile", ".zshrc"]:
        file = home / name
        if file.is_symlink():
            raise RuntimeError(f"{file} is a symbolic link; configure it explicitly")
        original = file.read_bytes() if file.exists() else b""
        text = original.decode("utf-8")
        if START in text or END in text:
            if text.count(START) != 1 or text.count(END) != 1 or text.index(START) >= text.index(END):
                raise RuntimeError(f"The Jerd block in {file} needs manual review")
            begin = text.index(START)
            finish = text.index(END) + len(END)
            text = text[:begin] + text[finish:].lstrip("\n")
        updated = text.rstrip("\n") + "\n\n" + BLOCK
        updates.append((file, original, updated.encode("utf-8")))

    backup = app / "shell-backups" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup.parent, 0o700)
    for file, original, updated in updates:
        saved = backup / file.name
        saved.write_bytes(original)
        saved.chmod(0o600)
        stage = file.with_name(file.name + ".jerd-tmp")
        with stage.open("xb") as output:
            os.chmod(stage, 0o600)
            output.write(updated)
            output.flush()
            os.fsync(output.fileno())
        if file.exists():
            shutil.copymode(file, stage)
        os.replace(stage, file)
    staged_tool = directory / ".JerdCLI-next"
    shutil.copyfile(source, staged_tool)
    staged_tool.chmod(0o700)
    os.replace(staged_tool, directory / "JerdCLI")
    for command in commands:
        staged_link = directory / ("." + command.name + "-next")
        staged_link.symlink_to("JerdCLI")
        os.replace(staged_link, command)
    print("php, composer, and laravel now select the registered site's PHP, or the Jerd default outside a site.")
    print(f"Shell backups: {backup}")
    print("Run exec zsh -l in an existing terminal to load the PATH change.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=pathlib.Path, default=pathlib.Path("/Applications/Jerd.app"))
    args = parser.parse_args()
    setup(args.app, pathlib.Path.home())


if __name__ == "__main__":
    main()
