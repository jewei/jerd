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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=pathlib.Path, default=pathlib.Path("/Applications/Jerd.app"))
    args = parser.parse_args()
    home = pathlib.Path.home()
    app = home / "Library/Application Support/Jerd"
    config = json.loads((app / "configuration.json").read_text())
    runtime = next(r for r in config["runtimes"] if r["id"] == config["defaultRuntimeID"])
    executable = pathlib.Path(runtime["cliPath"])
    if not executable.resolve().is_relative_to((app / "runtimes").resolve()):
        raise RuntimeError("Select a bundled Jerd PHP runtime before setting up its CLI command")
    receipt = json.loads((executable.parent / "jerd-receipt.json").read_text())
    if hashlib.sha256(executable.read_bytes()).hexdigest() != receipt["fileSHA256"][executable.name]:
        raise RuntimeError("The installed PHP executable failed verification")
    directory = app / "bin"
    if directory.is_symlink():
        raise RuntimeError("The CLI directory must not be a symbolic link")
    directory.mkdir(mode=0o700, exist_ok=True)
    source = args.app / "Contents/MacOS/JerdCLI"
    if not source.is_file():
        raise RuntimeError("Build or install a Jerd app with its CLI companion first")
    companions = json.loads((app / "runtimes/cli-tools.json").read_text())
    for path in companions.values():
        if not pathlib.Path(path).is_file():
            raise RuntimeError("Open Jerd to install Composer and the Laravel installer first")
    commands = [directory / name for name in ("php", "composer", "laravel")]
    for command in commands:
        if command.exists() or command.is_symlink():
            if not command.is_symlink() or not (command.resolve().is_relative_to((app / "runtimes").resolve())
                    or command.resolve() == directory / "JerdCLI"):
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


if __name__ == "__main__":
    main()
