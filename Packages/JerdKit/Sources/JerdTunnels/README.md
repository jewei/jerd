# JerdTunnels

JerdTunnels runs cloudflared connectors for existing, remotely managed Cloudflare tunnels.
It never changes a Cloudflare account, a remote tunnel, a route, or DNS. It depends only on
JerdFoundation and JerdProcess.

## Main types

| Type | Purpose |
| --- | --- |
| `TunnelSupervisor` | The actor that the app uses: `load()`, `currentConfiguration()`, `snapshots()`, `snapshotUpdates()`, `suggestedPort()`, `useRuntime(at:)`, `save(_:token:)`, `remove(id:)`, `start(id:)`, `stop(id:)`, `stopAll()`, `connectStartupTunnels()`, and `log(id:)`. |
| `TunnelRegistration`, `TunnelConfiguration`, `TunnelRuntime` | The saved settings in `tunnels/settings.json`. |
| `TunnelStore` | The one reader and writer of the settings file and its backup. |
| `TunnelToken` | Checks a token and gives the values to redact. Its text is never in a description. |
| `TunnelSecretStore` (`TunnelSecretStoring`) | Keeps each token in the Keychain. |
| `CloudflaredConnector` (`TunnelConnecting`) | Launches, checks, and stops the connectors that Jerd owns. |
| `TunnelReconnectPolicy` | The pure reducer of each tunnel's lifecycle: backoff, readiness, and failures. |
| `TunnelAuthFailureClassifier` | Finds a token rejection in anchored cloudflared log lines. |
| `TunnelState`, `TunnelSnapshot`, `TunnelStartupFailure` | What the app shows. `TunnelSnapshot.settingsIssue` tells the user to edit settings that an earlier build saved and the current rules refuse. |

## Rules

- The token is only in the Keychain and in the `TUNNEL_TOKEN` variable of the child. It is not
  in settings, in arguments, or in logs. The log replaces the token and its secret with
  `[redacted]`. A process of the same user can read a child environment (`ps -E`).
- Keychain item: generic password, service `dev.jerd.cloudflared.tunnel-token`, account = the
  registration UUID in upper case, accessible after first unlock, this device only.
- Load and Save never connect. `connectStartupTunnels()` connects only when the app calls it,
  and it returns every failure.
- A launch holds `service.lock`. It refuses a live earlier process before it runs any command.
  Then it checks the runtime version and that the metrics port is free, and writes `{}` to
  `config.yml`, so cloudflared reads no other configuration.
- Each launch moves the earlier output to `server.previous.log` (at most 4 MiB). The token
  check reads only the output of the current run.
- "Connected" means that `http://127.0.0.1:<metricsPort>/ready` answers 200 and that the owned
  process is the only listener, on that port only. Jerd never calls the public hostname.
- Backoff after an exit: 2, 5, 15, 30, then 60 seconds. It starts again at 2 seconds after
  30 seconds of connection. A retry stops at an error that needs the user.
- A retry continues only after a timeout, or after a launch failure with
  `TunnelRetryableError`. The connector uses that error when it exited before Jerd could check it. Every other
  process failure, for example a missing executable or a log that cannot be opened, needs the user.
- Failed-start limit: a start fails when its launch fails with a retryable error. It also fails
  when the connector exits within 15 seconds of its launch before any ready check. After 5
  failed starts in a row, the retries stop. The tunnel then shows "The tunnel process failed to
  start 5 times in a row, …" with the last error. A ready check sets the count to 0. A connector that ran longer
  than 15 seconds and then exited (for example while the network is down) is retried without
  a limit.
- Each tunnel has one work slot, keyed by generation (`TunnelWorkSlots`). Work clears only its
  own slot, and a result of older work changes nothing. When a generation ends with a failure,
  its monitor clears its slot, so Connect, Edit, Remove, and a runtime change work without Stop.
- Hostname: Save refuses an IP address (a last label of digits). Load still accepts it, with the
  rule of earlier builds, so their settings stay readable; `settingsIssue` asks for an edit.
- Stop sends SIGTERM and waits 30 seconds. It never sends SIGKILL. A connector that does not
  stop stays owned, Remove is refused, and `stopAll()` throws so that the app cancels Quit.

## Files

`tunnels/settings.json`, `settings.previous.json`, and for each registration
`tunnels/instances/<UUID>/` with `service.lock`, `active-run.json`, `config.yml`, `server.log`,
`server.previous.log`, and `home/`. Remove keeps the instance folder.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdTunnelsTests
```

The tests use fakes for the connector, the Keychain, the processes, the commands, and the clock.
One test runs a small fake `cloudflared` script. No test starts a tunnel or uses the network.

No test has a deadline that a slow machine can miss. The backoff and readiness tests move a
manual clock. The supervisor tests wait for the event that they need. It is a change from
`snapshotUpdates()`, a call that reaches the fake connector, or a sleeper on the manual clock.
Only the fake `cloudflared` test checks its log again each millisecond, without a deadline. Each
suite that waits has `.timeLimit(.minutes(1))`, which only stops a test that hangs.

The opt-in Keychain test runs the real `SecItem` calls with a throwaway service name and deletes
its item at the end:

```sh
JERD_KEYCHAIN_INTEGRATION=1 swift test --package-path Packages/JerdKit --filter TunnelKeychainIntegrationTests
```
