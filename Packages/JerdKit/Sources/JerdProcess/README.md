# JerdProcess

JerdProcess starts, watches, and stops the unprivileged processes of Jerd. It also keeps
bounded and redacted logs, saves run records, recovers processes after a crash, and
checks loopback listeners. It depends only on JerdFoundation.

## Main types

| Type | Purpose |
| --- | --- |
| `ProcessRequest`, `SpawnPlan` | What to start, and the exact `argv`, environment, and descriptors. |
| `ProcessSupervisor` (`ProcessControlling`) | Owns children by `ProcessToken`, reads states, and stops groups. |
| `StopPolicy`, `StopOutcome`, `StopCeiling` | The forceful and the graceful stop, the result of a stop, and the strongest stop of a supervisor. |
| `ProcessGroupInspector` | Lists live group members: `empty`, `members`, or `unknown`. |
| `ProcessTree` | Finds live descendants by parent chain, also those that left the group. |
| `ProcessLogFile` | Creates, trims, rotates, and reads a log file. |
| `LogRedactor` | Replaces secrets with `[redacted]` in a byte stream or a text. |
| `CommandRunner` (`CommandRunning`) | Runs one command with a timeout and cancellation. |
| `ProcessIdentity`, `AuditedSignaller` | Identify a process and signal it through its audit token. |
| `ActiveRunRecord`, `ActiveRunRecordFile` | The saved run record and its only reader and writer. |
| `StartGate`, `StartClearance`, `ActiveRunRecorder` | Block a start while an old process lives, then save the new record. |
| `RecoveryClassifier`, `ProcessObservation` | Pure rules: stale, recoverable, managed, or manual. |
| `ProcessRecoveryService` | Lists records and stops verified orphan processes on request. |
| `LoopbackPortGuard`, `ListenerReport` | Check that a port is free and that a service owns its listeners. |

## Rules

- A child never runs as root. It gets a new process group, an empty signal mask, and
  default signal actions. Its standard input is `/dev/null`, and it gets only descriptors
  0, 1, and 2 (and 3 and 4 for inherited listeners). Its environment is explicit. Nothing is inherited.
- An exited leader stays unreaped until its stop completes. A group signal can then reach
  only processes that Jerd started.
- A stop first records the descendants of the running leader by parent chain. A descendant
  that left the group (`setsid`, `setpgid`) gets each group signal by PID, after a check of
  its start time. It blocks `.stopped` until it exits.
- The graceful policy never sends `SIGKILL`. A timeout keeps the process owned.
- `ProcessSupervisor()` has the `.graceful` ceiling: it never sends `SIGKILL`, whatever policy
  a caller passes. Only `ProcessSupervisor(ceiling: .forceful)` (Caddy, PHP-FPM, commands) kills.
- The forceful policy waits a bounded time after `SIGKILL` for an empty group.
- A child that something else reaped is `notOwned`. It gets no signal, also when the reap
  happens during a stop.
- A command that survives its cleanup is reported with its PID. Its log is closed, and Jerd
  reaps it when it exits.
- Logs above 8 MiB are trimmed in place to the last 4 MiB (commands also keep the first
  1 MiB). A log that is a link or has another owner is refused.
- Command output goes to a new private temporary folder, never to the working folder.
- A saved PID alone is never signalled. Recovery signals only through the audit token.
- A run record is written or deleted only while its lock is held: every public write takes
  the lock. A new record never replaces an existing one, so a second start with the same
  `StartClearance` cannot hide a live process. Recovery saves verified group members and
  descendants outside the group before it sends a signal, and it uses the recorded signal.
- A service port must have no listener on any address, also not a wildcard listener.
  The bind check uses `SO_REUSEADDR` and never `SO_REUSEPORT`.

## Decisions and known gaps

- The redaction marker is `[redacted]` everywhere. Old builds used `[redacted]` in messages
  and `[REDACTED]` in logs. No code parses a log, so no saved data depends on the marker.
- `InstanceLock.acquire` creates a missing lock file, also in recovery. This is on purpose.
  Recovery runs only for a folder that has a record. The lock file is the exclusion with
  managers and with old builds. Without it, a record could not be recovered.
- A descendant that leaves the group is found only while its parent runs. When a leader exits
  before a stop or a recovery starts, `launchd` adopts its children and nothing links them to
  the record. A start then sees only the leader's group.
- Late output of a process outside the group, after its log closed, is read and dropped. The
  writer never gets `SIGPIPE`.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdProcessTests
```

The tests compile the C fixtures in `Tests/JerdProcessTests/Fixtures` with `/usr/bin/cc`.
They use temporary folders and loopback ports above 1023. They do not need root.
Tests of audited signals run only when the system supports them.
