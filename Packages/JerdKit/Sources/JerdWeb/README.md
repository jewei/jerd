# JerdWeb

JerdWeb serves the registered `.test` sites over HTTPS. It keeps the site configuration,
validates sites, and renders the Caddy, PHP-FPM, and PHP INI files. It runs the unprivileged
processes, and applies each site change as one transaction. It depends only on
JerdFoundation and JerdProcess. It does not import JerdSystem: the helper is a port.

## Main types

| Type | Purpose |
| --- | --- |
| `AppConfiguration`, `Site`, `DevelopmentRuntime`, `CaddyRuntime` | The saved `configuration.json`. |
| `ConfigurationCodec`, `ConfigurationStore` | The exact JSON form, the version 0 migration, the only writer. |
| `PathCanonicalizer`, `ProjectDetector`, `SiteValidator` | Canonical paths, Laravel detection, site rules. |
| `SiteChange`, `SiteChangeReducer`, `SiteRegistry` | One edit, its candidate, and the compare-and-swap save. |
| `ServingPlan`, `ExecutableStamp` | What a run serves, its equivalence rule, and binary identity. |
| `ForwardedHosts` (`ForwardedHostsLoading`) | The saved public hostnames that each site restores as Host from a forwarder. |
| `RunLayout`, `LocalAuthority` | Every path of a run and the one name of the CA. |
| `CaddyConfigRenderer`, `SiteRoutePolicy`, `ForwardedHostRoutePolicy`, `FPMPoolRenderer`, `PHPIniPolicy` | The generated files. |
| `InstallationIdentity`, `LocalCAProvisioner`, `PHPCABundleBuilder` | The installation CA and the PHP CA bundle. |
| `FastCGIPing` (`FPMPinging`) | The FPM readiness ping over the pool socket. |
| `PHPRuntimeInspector`, `CaddyRuntimeInspector` | Inspection of explicit executables into records. |
| `EngineRunner` (`EngineControlling`) | Starts, checks, watches, and stops Caddy and PHP-FPM. |
| `EnvironmentCoordinator` (`EnvironmentCoordinating`) | Keeps, replaces, or stops a run. |
| `SystemSetupGateway` (`SystemSetupManaging`) | Prepares, applies, and restores the HTTPS setup. |
| `SiteChangeTransaction` | Edits, Start, Stop, and forwarded host applies as one transaction with one rollback. |

Ports that JerdLive implements: `SystemSetupPort` (the helper), `TrustDecisionPort` (macOS
trust), `TrustProbing` (the system HTTPS check, with the live `SystemTrustProbe`), and
`ForwardedHostsLoading` (the saved local tunnel routes).

## Rules

- Detection reads file metadata only. Jerd never runs project code to detect a project.
- Caddy gets JSON only, with the admin API off, the internal CA only, and `install_trust: false`.
  It uses loopback or inherited listeners only and strict SNI. Unknown hosts get 421, and HTTP
  gets 308 to HTTPS.
- Within a matched site, only an exact `X-Forwarded-Host` of that site's forwarded hosts
  replaces the Host, with the saved name. Other values do not change the Host.
- Forwarded hosts never block a site change: when they cannot be read, the hosts of the current
  run stay. `SiteChangeTransaction.applyForwardedHosts(servingSite:)` waits for a running change,
  restarts only for a changed mapping, and runs the restart in its own task.
- Dot paths, private folders, Composer files, and PHP-like names (`.php5`, `.pht`, `.phtml`,
  `.phar`, `.phps`, `.phpt`, `.inc`, any case) answer 404. An existing file below `/.well-known/`
  is served statically; hidden files there still answer 404.
- PHP-FPM runs only the script that the routes selected (`SCRIPT_FILENAME`), never a file named
  by path info. Two layers make this true, and each one alone passes the attack requests of
  `ScriptSelectionIntegrationTests`: `cgi.fix_pathinfo = 1` (FPM uses `SCRIPT_FILENAME`, not
  `PATH_TRANSLATED`), and the PHP route sends path info only as `PATH_INFO`, so Caddy sends no
  `PATH_TRANSLATED`. So `/index.php/storage/upload.php` runs `index.php` with
  `PATH_INFO=/storage/upload.php`, and `/index.php/route` works.
- A script runs only when its name on disk ends in lowercase `.php`, also on a case-insensitive
  volume. The PHP route's `file` matcher ends in a glob class (`ph[p]`), which Caddy compares
  case-sensitively. `/name.php` for `name.PHP` and `/Name.php` for `name.php` answer 404.
- PHP and FPM end a request after 30 seconds. Caddy waits 35 seconds, so PHP decides.
- Caddy and PHP-FPM never run as root. Each run has a new private socket folder. The engine
  removes only a folder that it created, and deletes a run record only for a proven stop.
- Readiness uses CA-verified HTTPS with the run's CA. Never `curl -k`.
- A Stop raises a stop epoch. Every step of an older operation ends with `CancellationError`.
  A change takes its ticket when it holds the gate, before its first step. `SiteChangeTransaction.requestStop()`
  is the app's Stop: it ends the change, prevents its restart, and stops the run.
- An engine failure while an operation holds the coordinator gate is kept. It is applied when
  that operation ends, so the state never stays `running` after a runtime exit.
- A change asks for approval unless `ApprovalPredicate.approves` holds: every hostname, server
  TLS, and this installation's ID and CA fingerprint. A missing CA also needs an approval.
- Only `SiteChangeTransaction` rolls back. A failure restores the settings, the HTTPS setup,
  and the previous run once, and reports once.
- An approval covers every registered hostname. Removed or renamed hostnames leave the set.
- Ports 80 and 443 are checked once, right before the helper leases them.
- Corrupt configuration and identity files stay in place. Load and save then fail.

## Files

All paths come from `DataLayout`. Each PHP runtime has its own pool folder
`environment/php/<runtime UUID>/` (configuration and log). Caddy uses
`environment/configuration/caddy.json` and `environment/logs/caddy.log`.

The old app kept its first pool in `environment/configuration/php-fpm.conf`,
`environment/configuration/php.ini`, and `environment/logs/fpm.log`. A start removes these
files (`LegacyPoolFiles`). It does so only while it holds the records lock with no recorded
process alive, and only when Jerd provably wrote them. The configuration files must hold the
old generated text, and the log must be a regular file, not a link. Every other item stays.

## For the CLI target

Use `ConfigurationCodec.store(in:)` to read the configuration, `PHPIniPolicy.cliFile(caBundle:)`
for the CLI INI, and `PHPCABundleBuilder.prepareForCLI(layout:)` for the CA bundle.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdWebTests
```

The default tests use temporary folders, fakes, and loopback ports above 1023. Opt-in tests
need `JERD_WEB_INTEGRATION=1`, `JERD_PHP_CLI`, `JERD_PHP_FPM`, and `JERD_CADDY` (and optionally
`JERD_SECOND_PHP_CLI` and `JERD_SECOND_PHP_FPM`). They use an isolated CA and change no
system trust.
