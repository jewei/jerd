# Run tests

Run `./dev test` from the repository root. It runs the unit tests of every
target in `Packages/JerdKit`. To test one target, name it:

```sh
./dev test JerdWeb
```

Default tests need no root access, no network, and no system changes.
Tests that need real runtimes are opt-in. `./dev test` removes every inherited
`JERD_*` variable. `./dev test --integration web,database,mail,storage` sets
only the switches of the selected groups (for example `JERD_INTEGRATION=1`) and
passes through the runtime path variables of those groups. Set each path to an
absolute path of a trusted local runtime. The variables of each group are in
[Tools](../Tools/README.md#integration-tests).

`--integration database` also installs MySQL and PostgreSQL on demand through
the app wiring (`LiveDomain` and its one installer) into a temporary data root
(`OnDemandRuntimeIntegrationTests` in JerdLive), then starts and stops a
service with each. The MySQL install checks the pinned OpenPGP signature. The
downloads come from `.build/runtimes/downloads` through a local file server
inside URLSession, so the test needs no internet. `./dev runtimes prepare
database` keeps the MySQL signature file there too. `JERD_RUNTIME_DOWNLOADS`
names another folder of files named by SHA-256, and `JERD_ON_DEMAND_ENGINE`
selects engines (`mysql,postgresql` by default).

Without `--verbose`, a test run shows failures with their details, diagnostics,
and the final count. A failed run writes its full output to `.build/logs`.

## Temporary folders

Every test target uses the one `TemporaryDirectory` of the test-only target
`JerdTestSupport` (`Packages/JerdKit/Tests/JerdTestSupport`). Do not add another
copy. Add `JerdTestSupport` to the dependencies of a new test target instead.

```swift
let folder = try TemporaryDirectory(" café")  // optional suffix, to test quoting
defer { folder.remove() }
```

The folder has mode 0700 and a canonical path (`/private/var/…`). Its helpers
are `path`, `folder`, `file`, and `names(withPrefix:)`. The free functions
`contents` and `text` read a file. Helpers that only one target needs stay in
that target, for example `TemporaryDirectory+Layout.swift` in `JerdLiveTests`.

## Fixture processes

Some tests start small C fixtures, for example `graceful-process`, which ignores
SIGTERM. Each fixture runs with its working folder in the temporary folder of its
test. `TemporaryDirectory.remove()` finds each process that still runs in that
folder. It waits 5 seconds, kills each process that did not stop, and records a
test issue. Thus a test that fails before its Stop does not leave a fixture
running, and a test that leaves a fixture running fails.

## Signed XPC check

`SignedXPCCheckTests` (in `JerdSystemTests`) proves that the helper XPC
connection accepts only the Jerd code identities. It needs an Apple
code-signing identity, so it runs only when `JERD_XPC_IDENTITY` is set. It signs
a copy of the `JerdXPCCheck` probe as `dev.jerd.app` and checks that XPC refuses
a wrong client identity and a wrong server identity. Run it with `./dev`, which
also fails when the test is skipped and writes an evidence record to
`.build/evidence`:

```sh
./dev check xpc --identity "Apple Development: Name (TEAMID)"
```

To run the test directly:

```sh
JERD_XPC_IDENTITY="Apple Development: Name (TEAMID)" \
  swift test --package-path Packages/JerdKit --filter SignedXPCCheckTests
```

`./dev test` removes `JERD_XPC_IDENTITY` with the other inherited `JERD_*`
variables, so a normal test run skips this check.

## Debug variables of the app

Only a Debug build reads these variables. A Release build ignores them and
always uses `~/Library/Application Support/Jerd`.

| Variable | Effect |
| --- | --- |
| `JERD_DEBUG_DATA_ROOT=/absolute/path` | Use this folder as the data root instead of the data of the user. Use an empty folder to test a first launch. A relative path is ignored. |
| `JERD_DEBUG_KEEP_LAUNCHER=1` | Do not refresh the `php`, `composer`, and `laravel` command-line launcher. Use it when a test run uses the data of the user and must keep the launcher of the user. |

For example, build the Debug app with `./dev build`, then start it with an
empty data folder:

```sh
JERD_DEBUG_DATA_ROOT="$(mktemp -d)" \
  .build/xcode/Build/Products/Debug/Jerd.app/Contents/MacOS/Jerd
```

## App log

The app writes its lifecycle, launch, bundled runtime setup, and service start
and stop events to the unified log with the subsystem `dev.jerd.app`. The
categories are `lifecycle`, `launch`, `bundled-runtimes`, and `services`. To
show the events of the last hour:

```sh
/usr/bin/log show --last 1h --info --predicate 'subsystem == "dev.jerd.app"'
```

To follow new events while the app runs:

```sh
/usr/bin/log stream --info --predicate 'subsystem == "dev.jerd.app"'
```
