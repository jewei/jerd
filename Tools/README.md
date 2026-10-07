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
missing. After SIGINT, SIGTERM, or SIGHUP, the status is 128 plus the signal number.
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
`Info.plist`, the Sparkle keys, and arm64-only executables. The runtime payloads
are arm64 only, so `Configuration/Base.xcconfig` sets `ARCHS = arm64`.

The Xcode phase `Scripts/embed-app-contents.sh` calls `./dev runtimes embed`.
That command copies only the groups that `Runtimes/runtimes.json` marks
`"embedded": true` (`PayloadInventory.embeddedGroups`): development, mail, and
storage. The database runtimes are not in the app; the app installs them on
demand from the same pins. The command verifies every embedded payload before it copies. The receipt must
match its pin in `Runtimes/runtimes.json`. Every file must match its SHA-256
and executable flag. It copies with `rsync --delete`, so an unchanged payload is
not copied again, and it removes folders that no embedded pin names. The script calls
`./dev` and does not check the files itself. The receipt rules are in
JerdManifest and JerdRuntimes, the same code that the app uses to install the
payloads. The `dev` shim rebuilds `jerd-dev` only when a Tools source changes,
so a build from Xcode works too.

A Release build requires every payload of an embedded group. A Debug build
embeds the prepared payloads of those groups and warns about missing ones. `./dev check` and CI build
Release with `--allow-missing-runtimes`, which turns the gate off for an
unsigned check build only.

## Runtime payloads

| Command | Purpose |
| --- | --- |
| `./dev runtimes prepare [GROUP...]` | Download, verify, and prepare the pinned payloads. Default: every group |
| `./dev runtimes verify [GROUP...]` | Verify each payload against its pin and receipt, file by file |
| `./dev runtimes status` | List each payload with its group, whether the app embeds it, its version, size, and state |
| `./dev runtimes embed DEST [--require-all]` | Verify and copy the payloads of the embedded groups into an app; the Xcode phase calls it |

Groups: `development` (PHP, Caddy, Composer, Laravel installer), `database`
(MySQL, PostgreSQL, Redis), `mail` (Mailpit), `storage` (RustFS), and `xz` (the
reviewed XZ library of RustFS; `storage` selects it too). Names ignore case,
and `Support/XZ` names the library.

`prepare` prepares every group, also the database group that the app does not
embed: CI and the integration tests use those payloads. It uses
`PinnedPayloadPreparer`, the same pipeline as managed runtime updates and the
on-demand database installation in the app. The output is `.build/runtimes/payloads/<group>/<payload
ID>/` with `payload-receipt.json`, and a copy of the catalog. A payload that
exists is verified and kept. A payload of an older pin is preserved and stops
the run; remove `.build/runtimes/payloads` and prepare again. Downloads are kept
in `.build/runtimes/downloads/<sha256>`; only a file with the pinned digest goes
into or comes out of that cache.

Prerequisites: an arm64 Mac and Xcode. Redis and XZ build with the Xcode
compiler. The MySQL signature is checked in Swift with Oracle's pinned key, so
GnuPG is not needed. XZ builds into `.build/runtimes/support/xz` with a fixed
environment and the `MACOSX_DEPLOYMENT_TARGET` of `Configuration/Base.xcconfig`.
Its `support-receipt.json` records the pin, the deployment target, and the file
digests, so a later run reuses the build.

## Integration tests

`./dev test` removes every inherited `JERD_*` variable. Only the variables of
the groups in `--integration` reach the tests. The paths come from the receipts
of the prepared payloads, so no file name, for example a PHP version, is in the
tool. Every payload is verified before a test uses it. When you set every
required path of a group, your paths win; set them to absolute paths of trusted
local runtimes.

| Group | Required | Optional |
| --- | --- | --- |
| `web` | `JERD_PHP_CLI`, `JERD_PHP_FPM`, `JERD_CADDY` | `JERD_SECOND_PHP_CLI`, `JERD_SECOND_PHP_FPM`, `JERD_KEEP_TEST_FILES` |
| `database` | `JERD_DATABASE_RUNTIMES` | `JERD_OCCUPIED_DATABASE_PORT`, `JERD_RUNTIME_DOWNLOADS`, `JERD_ON_DEMAND_ENGINE` |
| `mail` | `JERD_MAIL_RUNTIME` | |
| `storage` | `JERD_STORAGE_RUNTIME` | |

The `database` group also sets `JERD_ON_DEMAND_INTEGRATION=1` and
`JERD_RUNTIME_DOWNLOADS=.build/runtimes/downloads` when that folder exists, so the
on-demand installation test runs from the verified downloads without internet.
Each group also sets `JERD_INTEGRATION=1`. The `database`, `mail`, and
`storage` groups also set their own switch, for example
`JERD_MAIL_INTEGRATION=1`. The database tests read a folder with `pins.json`
and one folder for each engine. `./dev` writes that index in
`.build/runtimes/integration/database` with links to the payloads, so the
payloads stay unchanged.

CI runs the `runtime-integration` job weekly and on manual dispatch. It caches
`.build/runtimes` with a key on `Runtimes/runtimes.json` and the Laravel lock
file, then runs `./dev runtimes prepare`, `./dev runtimes verify`, and
`./dev test --integration web,database,mail,storage`.

## Pinned versions

| File | Pins |
| --- | --- |
| `../.xcode-version` | The Xcode that the repository is tested with. CI selects it. |
| `xcodegen-version` | The XcodeGen version. CI installs it after a SHA-256 check. |
| `Package.resolved` | `swift-argument-parser`. |

`./dev doctor` shows a warning when a local version is different.

## Release

`./dev release` makes signed app updates on the Mac that holds the keys. The
Developer ID key, the Sparkle key (Keychain account `dev.jerd.sparkle`), and the
notary profile stay in the Keychain. The identity, team, and profile are options.

1. `./dev release bump --version V --build B` sets `Configuration/Version.xcconfig`
   and moves the `## [Unreleased]` notes under `## [V] - date` in `CHANGELOG.md`.
   Merge this change through a pull request. The tag then names the exact commit
   that Apple notarizes.
2. `./dev release prepare --version V --build B --minimum-macos M --identity ID
   --team T` needs a clean worktree at that commit and every prepared payload. It
   archives and signs the payloads and Sparkle with explicit identifiers. It runs the
   runtime tests, notarizes the app and the disk image, and signs the feed. It writes
   a private candidate in `.build/releases/Jerd-V-B-*` (mode 0700). Nothing is public.
3. `./dev release validate DIR` checks the candidate again. `--public-key-only`
   uses no Keychain, so any Mac can run it.
4. `./dev release publish DIR` requires the source commit on `origin/main` and no
   tag or release of the version. It creates a draft, checks the uploaded assets,
   publishes the release, and opens a pull request with the signed feed. It never
   pushes to `main`. Merge the pull request, then run `./dev release resume DIR`.
   Publication ends when the public feed URL serves the signed feed.

`state.json` in the candidate records each stage. `./dev release status DIR` shows
the stage and the next action. `resume` continues from the recorded stage, and each
step can run again safely. `./dev release clean [--keep N]` removes old candidates
(about 2.5 GB each), but never one whose publication started and is not finished.

The feed item uses `<description sparkle:format="plain-text">` with the notes of
the changelog section, so Sparkle shows the Markdown text as it is.

## Manual checks

These two harnesses need an Apple code-signing identity in the Keychain, so CI
does not run them. Each one writes a dated JSON evidence record to
`.build/evidence/<UTC date>-<check>.json`. The record gives the macOS and Xcode
versions, the commit, the dirty state of the worktree, and the result of each
case. A failed run also writes a record.

| Command | What it proves |
| --- | --- |
| `./dev check updates --identity ID` | Sparkle installs only signed updates. It compiles `Fixtures/AppUpdateTest.swift` with the resolved Sparkle (run `./dev build` first) and signs version 1 and version 2 of a temporary test app. Each case serves a feed signed with a temporary key on `127.0.0.1`. The cases are `no-update`, `altered-feed`, `altered-archive`, `success`, and `refused-quit`. The test apps copy the Sparkle keys of `Apps/Jerd/Resources/Info.plist` and never load Jerd settings or services. At the end the check stops only its own test processes, removes the preferences and caches of the random bundle identifier, and removes `.build/check-updates-*`. |
| `./dev check xpc --identity ID` | Signed XPC accepts only the Jerd code identities. It runs the JerdKit test `SignedXPCCheckTests` (it signs the `JerdXPCCheck` probe) with `JERD_XPC_IDENTITY=ID`. The check fails when the test does not run or is skipped. |

## Code layout

| Folder | Contents |
| --- | --- |
| `Sources/JerdDevKit/Process` | The process runner: argument arrays, time limits, separate output |
| `Sources/JerdDevKit/Planning` | Pure plans: the exact command that each command runs |
| `Sources/JerdDevKit/Policies` | Pure repository policies that `./dev lint` checks |
| `Sources/JerdDevKit/Steps` | Steps that run plans and policies and report results |
| `Sources/JerdDevKit/Runtimes` | Payload preparation, verification, embedding, the XZ build, and integration paths |
| `Sources/JerdDevKit/Release` | The release pipeline and its `state.json` state machine |
| `Sources/JerdDevKit/Checks` | The manual harnesses and their evidence records |
| `Sources/JerdDevKit/Commands` | One file for each command; `CommandCatalog` lists them |
| `Scripts/embed-app-contents.sh` | The Xcode build phase that embeds the helper, CLI, and runtimes |
| `Fixtures` | Swift sources that the harnesses compile at run time; not part of the package |

The package uses the JerdKit products `JerdManifest` and `JerdRuntimes`, so the
tool and the app share one set of receipt, pin, and feed rules.

To add a command, add one file in `Commands/` and one entry in `CommandCatalog`.
