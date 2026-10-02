"""Shared file and command checks for Jerd's local release tools."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPARKLE = ROOT / ".build/SourcePackages/artifacts/sparkle/Sparkle/bin"
FEED_URL = "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml"
REPOSITORY = "jewei/jerd"
SPARKLE_ACCOUNT = "dev.jerd.sparkle"
MACHO_MAGIC = {bytes.fromhex(x) for x in ["feedface", "cefaedfe", "feedfacf", "cffaedfe",
                                       "cafebabe", "bebafeca", "cafebabf", "bfbafeca"]}


def parallel_each(function, values):
    """Keep at most four operations active; stop scheduling on the first failure."""
    iterator = iter(values)
    with ThreadPoolExecutor(max_workers=4) as pool:
        pending = {pool.submit(function, value) for value in list_next(iterator, 4)}
        while pending:
            complete, pending = wait(pending, return_when=FIRST_COMPLETED)
            for future in complete:
                future.result()
            pending.update(pool.submit(function, value) for value in list_next(iterator, len(complete)))


def list_next(iterator, count):
    for _ in range(count):
        try:
            yield next(iterator)
        except StopIteration:
            return


def run(*args, cwd=None, env=None, log=None, timeout=300):
    command = [str(x) for x in args]
    if log is not None:
        # Build output can be large. Keep it on disk while the command runs.
        with pathlib.Path(log).open("ab") as stream:
            try:
                result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=timeout)
            except subprocess.TimeoutExpired as error:
                stream.write(b"\nCommand timed out. Earlier output is retained above.\n")
                raise RuntimeError(f"{pathlib.Path(command[0]).name} timed out; see {log}") from error
        with pathlib.Path(log).open("rb") as stream:
            stream.seek(max(0, stream.seek(0, os.SEEK_END) - 65536))
            output = stream.read().decode("utf-8", errors="replace")
    else:
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
        output = result.stdout if result.returncode == 0 else (result.stderr or result.stdout)
    if result.returncode:
        raise RuntimeError(f"{pathlib.Path(str(args[0])).name} failed ({result.returncode}): "
                           + output[-4000:])
    return output.strip()


def digest(path):
    result = hashlib.sha256()
    with pathlib.Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def write_json(path, value):
    pathlib.Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,99}", value):
        raise ValueError("Invalid release identifier")
    return value


def regular_file(root, name):
    relative = pathlib.PurePosixPath(name)
    if not name or relative.is_absolute() or any(x in ("", ".", "..") for x in name.split("/")):
        raise ValueError("Invalid payload path: " + name)
    path = pathlib.Path(root) / relative
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(pathlib.Path(root).resolve()):
        raise ValueError("Payload file is not a regular file within its directory: " + name)
    for parent in path.parents:
        if parent == pathlib.Path(root):
            break
        if parent.is_symlink():
            raise ValueError("Payload parent is a symbolic link: " + name)
    return path


def is_macho(path):
    with pathlib.Path(path).open("rb") as source:
        return source.read(4) in MACHO_MAGIC


def macho_details(path):
    """Read dependency commands, excluding the dylib's own LC_ID_DYLIB name."""
    output = run("/usr/bin/otool", "-arch", "arm64", "-l", path)
    result = {"dependencies": [], "rpaths": [], "minimum": "0.0", "library": False}
    command = None
    dependency_commands = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB",
                           "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB"}
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        key, value = fields
        if key == "cmd":
            command = value
            if command == "LC_ID_DYLIB":
                result["library"] = True
        elif key == "name" and command in dependency_commands:
            result["dependencies"].append(value.split(" (offset ", 1)[0])
        elif key == "path" and command == "LC_RPATH":
            result["rpaths"].append(value.split(" (offset ", 1)[0])
        elif key == "minos" and command == "LC_BUILD_VERSION":
            result["minimum"] = value
        elif key == "version" and command == "LC_VERSION_MIN_MACOSX":
            result["minimum"] = value
    return result


def version_tuple(value):
    if not re.fullmatch(r"\d+(?:\.\d+){0,3}", value):
        raise ValueError("Invalid numeric version: " + value)
    return tuple(int(x) for x in value.split(".")) + (0,) * (4 - len(value.split(".")))


def local_dependency(path, dependency, root, rpaths=(), relocate=False):
    """Resolve one bundled dependency without using libraries on the build Mac."""
    root = pathlib.Path(root).resolve()
    executable_dir = root / "bin" if (root / "bin").is_dir() else root

    def expand(value):
        if value.startswith("@loader_path/"):
            return path.parent / value.removeprefix("@loader_path/")
        if value.startswith("@executable_path/"):
            return executable_dir / value.removeprefix("@executable_path/")
        return pathlib.Path(value)

    if dependency.startswith(("/usr/lib/", "/System/Library/")):
        return None
    if dependency.startswith("@rpath/"):
        suffix = dependency.removeprefix("@rpath/")
        candidates = [expand(rpath) / suffix for rpath in rpaths]
        candidates += [root / "lib" / suffix, executable_dir / suffix]
    else:
        candidates = [expand(dependency)]
        if relocate and pathlib.PurePosixPath(dependency).name == dependency:
            candidates = [path.parent / dependency, root / "lib" / dependency]
        # Upstream archive links become regular files in Jerd. A copied plugin
        # can therefore need a new relative route to its canonical bundled library.
        if relocate and dependency.startswith("@loader_path/") and candidates[0].resolve().is_relative_to(root):
            candidates += [root / "lib" / pathlib.PurePosixPath(dependency).name,
                           executable_dir / pathlib.PurePosixPath(dependency).name]
    for candidate in candidates:
        if candidate.resolve().is_relative_to(root) and candidate.is_file() and not candidate.is_symlink():
            return candidate.resolve()
    raise ValueError(f"Unbundled dependency in {path.name}: {dependency}")


def require_clean_source(expected=None):
    if run("git", "status", "--porcelain", "--untracked-files=all", cwd=ROOT):
        raise RuntimeError("A release requires a clean worktree, including untracked files.")
    commit = run("git", "rev-parse", "HEAD", cwd=ROOT)
    if expected and commit != expected:
        raise RuntimeError("The source commit changed during release preparation.")
    return commit
