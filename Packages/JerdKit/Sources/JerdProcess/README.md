# JerdProcess

JerdProcess starts, watches, and stops the unprivileged processes of Jerd. It also keeps
bounded and redacted logs, saves run records, recovers processes after a crash, and
checks loopback listeners. It depends only on JerdFoundation.

## Main types

| Type | Purpose |
| --- | --- |
| `ProcessRequest`, `SpawnPlan` | What to start, and the exact `argv`, environment, and descriptors. |
| `ProcessSupervisor` (`ProcessControlling`) | Owns children by `ProcessToken`, reads states, and stops groups. |
| `StopPolicy`, `StopOutcome` | The forceful and the graceful stop, and the result of a stop. |
| `ProcessGroupInspector` | Lists live group members: `empty`, `members`, or `unknown`. |
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

- A child never runs as root. It gets a new process group, an empty signal mask, default
  signal actions, standard input from `/dev/null`, and only descriptors 0, 1, 2 (and 3, 4
  for inherited listeners). Its environment is explicit. Nothing is inherited.
- An exited leader stays unreaped until its stop completes. A group signal can then reach
  only processes that Jerd started.
- The graceful policy never sends `SIGKILL`. A timeout keeps the process owned.
- The forceful policy waits a bounded time after `SIGKILL`.
- A child that something else reaped is `notOwned`. It gets no signal.
- Logs above 8 MiB are trimmed in place to the last 4 MiB (commands also keep the first
  1 MiB). A log that is a link or has another owner is refused.
- Command output goes to a new private temporary folder, never to the working folder.
- A saved PID alone is never signalled. Recovery signals only through the audit token.
- A run record is written or deleted only while its lock is held. Recovery saves verified
  descendants before it sends a signal, and it uses the recorded signal.
- A service port must have no listener on any address, also not a wildcard listener.
  The bind check uses `SO_REUSEADDR` and never `SO_REUSEPORT`.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdProcessTests
```

The tests compile the C fixtures in `Tests/JerdProcessTests/Fixtures` with `/usr/bin/cc`.
They use temporary folders and loopback ports above 1023. They do not need root.
Tests of audited signals run only when the system supports them.
