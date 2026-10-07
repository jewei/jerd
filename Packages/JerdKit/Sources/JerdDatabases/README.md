# JerdDatabases

JerdDatabases manages independent MySQL, PostgreSQL, and Redis services. Each service has its
own UUID, port, data folder, password, lock, and process. It uses JerdServiceKit for the
lifecycle.

## Main types

| Type | Purpose |
| --- | --- |
| `DatabaseManager` | The registry of services and one `ManagedInstance` for each service. |
| `DatabaseServiceDefinition` | Identity, credentials, first initialization, and the launch plan of one instance. |
| `MySQLDefinition` | `--initialize-insecure`, a socket-only bootstrap server, then TCP on 127.0.0.1. |
| `PostgresDefinition` | `initdb` with SCRAM and a password file, `pgpass`, and `SIGINT` to stop. |
| `RedisDefinition` | `redis.conf` with protected mode and append-only files, and `REDISCLI_AUTH`. |
| `DatabaseConfiguration`, `DatabaseRuntime`, `DatabaseService` | The content of `services.json`. |
| `DatabaseIdentity`, `DatabaseCredentials`, `RemovedRegistration` | The markers in each instance folder. |
| `RetainedDatabase` | A data folder without a registration, which Restore can register again. |
| `DatabaseSnapshot`, `DatabaseConnection` | The page state and the Laravel settings. |

## Files

All paths come from `DatabasesLayout` in JerdFoundation. Folders have mode 0700 and files 0600.

- `databases/services.json` and `services.previous.json` (settings format).
- `databases/instances/<UUID>/`: `runtime.json`, `initialized.json`, `credentials.json`,
  `removed-registration.json`, `service.lock`, `active-run.json`, `server.log`, `data/`, and the
  engine files `client.cnf`, `pgpass`, or `redis.conf`.
- `$TMPDIR/jerd-db-XXXXXXXX-X/`: the socket folder of one run, with `owner.json`
  (`{"instance": "<instance folder>"}`). It is removed after the stop. After a crash, the first `load()`
  removes it with three conditions. The marker names an instance of this data root, the
  instance lock is free, and no saved process lives. Every other folder stays.

## Runtimes

A runtime record names a folder with `bin/`. Records of earlier versions name payloads that the
app bundle installed into `database-runtimes/`; they stay in use. The app embeds Redis and installs
MySQL and PostgreSQL on demand into `runtime-updates/` (see JerdLive) and registers it
with `registerRuntime`. Each build has its own ID, so a registered service never changes runtime.

## Rules

- A corrupt or unsupported `services.json` is never replaced.
- A service never changes its runtime. A runtime never changes under its ID (path included).
- A port of another registered service is a port conflict, not corrupt settings.
- Names are trimmed and have 1 to 80 characters.
- Data is never opened with another runtime identity. Partial data is never initialized again.
- A password never appears in an argument. Messages and log tails show `[redacted]`.
- Readiness requires the exact reply `42` (SQL) or `PONG` (Redis) within 45 seconds.
- `initdb` and `mysqld --initialize-insecure` run as owned processes of the instance. They
  have a run record and hold the lock. They stop with the graceful engine signal (`SIGINT`
  for PostgreSQL, `SIGTERM` for MySQL), never `SIGKILL`. After 120 seconds the initializer is stopped. When that stop also
  times out, the service is `stuck` with its lock and record, and Quit is cancelled until a Stop
  succeeds. Partial data is kept.
- `init-password`, `bootstrap.sql`, and `bootstrap.cnf` hold the password. They are removed when
  the initializer exits or the setup readiness check ends; a failed removal fails the start.
- Remove keeps every data file. A service that never created data leaves nothing to restore.
- Restore needs the exact original runtime, matching markers, a real `data/` folder, and valid credentials.
- Quit stops all services in parallel. Only a start, Edit, Remove, or Restore in progress refuses it.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdDatabasesTests
```

The default tests use fake commands and processes, golden files from older builds, and two C
fixtures from `JerdServiceKitTestSupport` that `DatabaseDescendantTests` starts as a fake
`redis-server`: `orphan-service` (a master that exits and leaves a child that ignores SIGTERM)
and `graceful-process` (a server that ignores SIGTERM, ends on SIGINT, and is paused).

The two opt-in tests start real runtimes on free loopback ports in a temporary folder.
`DatabaseIntegrationTests` checks authentication, data, stops, and restore for each engine.
`DatabasePauseIntegrationTests` pauses each server and checks that Quit still stops it
gracefully. Prepare the runtimes once, then run both through `./dev`, which writes the runtime
index:

```sh
./dev runtimes prepare database
./dev test JerdDatabases --integration database
```

Or run them directly:

```sh
JERD_DATABASE_INTEGRATION=1 JERD_DATABASE_RUNTIMES=<folder with pins.json> \
  swift test --package-path Packages/JerdKit --filter 'Database.*IntegrationTests'
```

`JERD_OCCUPIED_DATABASE_PORT=<port>` also checks that an existing wildcard listener blocks Add.
