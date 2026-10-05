# Tools

`Tools/` is the Swift package of `jerd-dev`, the tool behind `./dev`. For the
command list, see [AGENTS.md](../AGENTS.md#commands) or run `./dev help`.

## How `./dev` runs

1. The `dev` shim finds the repository root and checks that Xcode is selected.
2. SwiftPM builds `jerd-dev` in release mode into `Tools/.build/dev`. It builds
   again only when a Tools source changes. The test build uses another folder.
3. The tool runs from the repository root. Each command prints `==>` step
   headers. A command with more than one step ends with a summary.

Exit status: 0 success, 1 a check failed, 2 usage error, 3 a prerequisite is
missing, 128 plus the signal number after SIGINT, SIGTERM, or SIGHUP.
`--verbose` shows each underlying command line. `--json` prints one summary
object on standard output and sends every other line to standard error:

```json
{"command":"lint","exitStatus":0,"message":null,"status":"ok","steps":[{"messages":[{"level":"ok","text":"…"}],"seconds":0.2,"status":"ok","title":"Format check"}]}
```

Each child process leads its own process group. A time limit sends SIGTERM and
then SIGKILL to the whole group, and a signal to `./dev` goes to every running
group. A failed quiet step writes its full output to `.build/logs/<step>.log`;
CI uploads that folder when `./dev check` fails.

## Builds

Every build checks the built app: the update feed URL and public key in
`Info.plist`, the Sparkle keys, and arm64-only executables (`ARCHS = arm64` in
`Configuration/Base.xcconfig`, because the runtime payloads are arm64 only).

A Release build requires a file in `.build/runtimes/payloads/<Group>` for every
runtime group in `Runtimes/` with a pin file. `./dev check` and CI build Release
with `--allow-missing-runtimes`, which turns this gate off for an unsigned check
build only. The check of receipts and file digests comes with JerdManifest.

## Pinned versions

| File | Pins |
| --- | --- |
| `../.xcode-version` | The Xcode that the repository is tested with. CI selects it. |
| `xcodegen-version` | The XcodeGen version. CI installs it after a SHA-256 check. |
| `Package.resolved` | `swift-argument-parser`. |

`./dev doctor` shows a warning when a local version is different.

## Integration tests

`./dev test` removes every inherited `JERD_*` variable. Only the variables of
the groups in `--integration` reach the tests. Set each path to an absolute
path of a trusted local runtime.

| Group | Required | Optional |
| --- | --- | --- |
| `web` | `JERD_PHP_CLI`, `JERD_PHP_FPM`, `JERD_CADDY` | `JERD_SECOND_PHP_CLI`, `JERD_SECOND_PHP_FPM`, `JERD_KEEP_TEST_FILES` |
| `database` | `JERD_DATABASE_RUNTIMES` | `JERD_OCCUPIED_DATABASE_PORT` |
| `mail` | `JERD_MAIL_RUNTIME` | |
| `storage` | `JERD_STORAGE_RUNTIME` | |

Each group also sets `JERD_INTEGRATION=1`. The `database`, `mail`, and
`storage` groups also set their own switch, for example
`JERD_MAIL_INTEGRATION=1`. Later, `./dev runtimes prepare` sets the paths from
`.build/runtimes/payloads`.

## Code layout

| Folder | Contents |
| --- | --- |
| `Sources/JerdDevKit/Process` | The process runner: argument arrays, time limits, separate output |
| `Sources/JerdDevKit/Planning` | Pure plans: the exact command that each command runs |
| `Sources/JerdDevKit/Policies` | Pure repository policies that `./dev lint` checks |
| `Sources/JerdDevKit/Steps` | Steps that run plans and policies and report results |
| `Sources/JerdDevKit/Commands` | One file for each command; `CommandCatalog` lists them |
| `Scripts/embed-app-contents.sh` | The Xcode build phase that embeds the helper, CLI, and runtimes |

To add a command, add one file in `Commands/` and one entry in `CommandCatalog`.
