# JerdServiceKit

JerdServiceKit has the lifecycle that the data services share: databases, mail, and storage.
It depends only on JerdFoundation and JerdProcess. Tunnels do not use it.

## Main types

| Type | Purpose |
| --- | --- |
| `ServiceDefinition` | What one service adds: its profile, version probe, data preparation, and launch plan. |
| `ManagedInstance` | One data folder, one lock, at most one owned process, and the state machine. |
| `ServiceState`, `ServiceEvent` | The states and events. `ServiceState.applying(_:)` is the one transition rule. |
| `ServiceProfile`, `ServiceMessages` | Names, folders, ports, the stop signal, and the user messages. |
| `LaunchPlan`, `ReadinessCheck` | The process to start, its loopback ports, its probe, its secrets, its temporary items, and its stop hook. |
| `InitializerPlan`, `StartTools` | A one-shot process of a first start (for example `initdb`), and the owned steps that a definition can run. |
| `OwnedServiceProcess`, `ServiceLog` | A started process with its record, and the rotated, redacted server log. |
| `ServiceEffects`, `TimeKeeping` | The ports for processes, commands, listeners, run records, and the clock. |
| `VersionProbe`, `VersionRule` | Require the registered version in the output of the runtime binary. |
| `ReadinessPoller` | Polls a probe until ready, exit, or the deadline, and redacts the last failure. |
| `DataIdentityGuard`, `InitializationMarker` | Tie data to its runtime identity. Never adopt or initialize partial data again. |
| `ServiceSettingsStore`, `MarkerFile` | Settings files and small private JSON markers. |
| `MaintenanceLease` | Exclusive use of a stopped instance with its lock held. |
| `RuntimeUpdateTransaction`, `RuntimeUpdateJournal` | Replace a runtime with a backup, a journal, and an automatic restore. |
| `BackupRetentionService`, `DirectorySize` | List and delete runtime update backups in Advanced. |
| `SingleServiceCoordinator`, `SingleServiceDescribing` | The manager core of Mail and Storage: load, one operation at a time, port edits under a lease, runtime registration, update, and recovery. |

## Start order

A start does these steps in this order. A failure stops the steps and keeps all data.

1. Every port is free on every address. No file is created before this check.
2. The instance folder exists (mode 0700). The lock is taken.
3. The start gate clears the run record. It removes a stale record only with the lock held.
4. The runtime binary reports the registered version.
5. The definition checks the data identity, the credentials, and the first initialization. An
   initializer or a setup phase runs as an owned process with a run record and the lock held.
6. The process starts, and its run record is saved.
7. The probe passes, the process owns exactly its loopback listeners and no UDP socket, and it
   is still alive.

## Rules

- A stop is graceful and never sends `SIGKILL`. A timeout gives `stuck`: the process, the lock,
  and the record stay. Only a later Stop leaves `stuck`. This holds for every owned process: a
  server, a setup phase, and an initializer (`StartTools.runInitializer`).
- A start failure keeps the kind of the error of the failed step.
- `refresh()` detects an exit, but it never waits for the stop of the group. A user Stop joins
  that stop. An exit stop never makes Quit fail.
- A child that something else reaped is checked through its record. A live group keeps the
  record and releases the lock, so that Process recovery can act.
- The secret files of a launch (`LaunchPlan.secretFiles`, for example a bootstrap SQL file with
  a password) are removed when its readiness check ends, passed or not. A later stop timeout
  cannot keep them. A failed removal fails the step and names the file.
- Each launch ends once: after its process stopped (Stop, exit, or a reap outside Jerd), or
  when the launch fails before a process is owned. Then its temporary items are removed and
  `LaunchPlan.didStop` runs, so a service can release resources that are not files, for example
  a URL session.
- A maintenance lease keeps the lock from the first step to the last, also during a restore.
- A runtime update that fails and restores a stopped service leaves it `stopped`; the error names
  the cause. A failed restore keeps the journal and the `failed` state.
- A runtime update copies each named item (an APFS clone when possible) off the actor, and
  flushes the copies to the drive (`fsync` on each item, then `F_FULLFSYNC`) before it writes the
  journal. A restore flushes the restored items before it removes the journal. Recovery uses the
  names in the journal, so a newer build can recover it.
- Backups stay until the user deletes them. A journal protects every backup of its service.
- `runtime-update.json` adds the key `schemaVersion` to the old `{id, names, present}` form, so
  its bytes differ from older builds. The old keys and value forms stay, and `names` keeps its
  order, so an older build reads a new journal after a downgrade (tested with a copy of the old
  struct).

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdServiceKitTests
```

The tests use fake processes, a fake `lsof`, a fake clock, and temporary folders. Some tests
compile C fixtures with `/usr/bin/cc` and start them. No test needs root or a network.

`Tests/JerdServiceKitTestSupport` holds the fakes and C fixtures that the service test targets
share (`FakeProcessController`, `FakeSystem`, `FakeTimeKeeper`, `ScriptedCommands`, `Gate`,
`TemporaryDirectory`, `LoopbackHTTPServer`, `goldenFixture`, and `Fixtures`). Only test targets
depend on it; the app never links it.
