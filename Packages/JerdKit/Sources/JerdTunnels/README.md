# JerdTunnels

JerdTunnels runs cloudflared connectors for existing, remotely managed Cloudflare tunnels.
It never changes a Cloudflare account, a remote tunnel, a route, or DNS. It depends only on
JerdFoundation and JerdProcess.

## Main types

| Type | Purpose |
| --- | --- |
| `TunnelSupervisor` | The actor that the app uses: load, save, remove, start, stop, stop all, and logs. |
| `TunnelRegistration`, `TunnelConfiguration`, `TunnelRuntime` | The saved settings in `tunnels/settings.json`. |
| `TunnelStore` | The one reader and writer of the settings file and its backup. |
| `TunnelToken` | Checks a token and gives the values to redact. Its text is never in a description. |
| `TunnelSecretStore` (`TunnelSecretStoring`) | Keeps each token in the Keychain. |
| `CloudflaredConnector` (`TunnelConnecting`) | Launches, checks, and stops the connectors that Jerd owns. |
| `TunnelReconnectPolicy` | The pure reducer of each tunnel's lifecycle: backoff, readiness, and failures. |
| `TunnelAuthFailureClassifier` | Finds a token rejection in anchored cloudflared log lines. |
| `TunnelState`, `TunnelSnapshot`, `TunnelStartupFailure` | What the app shows. |

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
- Each tunnel has one work slot, keyed by generation. A result of older work changes nothing.
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
