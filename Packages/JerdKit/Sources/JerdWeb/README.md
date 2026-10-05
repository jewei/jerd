# JerdWeb

JerdWeb serves the registered `.test` sites over HTTPS. It keeps the site configuration,
validates sites, renders the Caddy, PHP-FPM, and PHP INI files, runs the unprivileged
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
| `RunLayout`, `LocalAuthority` | Every path of a run and the one name of the CA. |
| `CaddyConfigRenderer`, `SiteRoutePolicy`, `FPMPoolRenderer`, `PHPIniPolicy` | The generated files. |
| `InstallationIdentity`, `LocalCAProvisioner`, `PHPCABundleBuilder` | The installation CA and the PHP CA bundle. |
| `FastCGIPing` (`FPMPinging`) | The FPM readiness ping over the pool socket. |
| `PHPRuntimeInspector`, `CaddyRuntimeInspector` | Inspection of explicit executables into records. |
| `EngineRunner` (`EngineControlling`) | Starts, checks, watches, and stops Caddy and PHP-FPM. |
| `EnvironmentCoordinator` (`EnvironmentCoordinating`) | Keeps, replaces, or stops a run. |
| `SystemSetupGateway` (`SystemSetupManaging`) | Prepares, applies, and restores the HTTPS setup. |
| `SiteChangeTransaction` | Edits, Start, and Stop as one transaction with one rollback. |

Ports that JerdLive implements: `SystemSetupPort` (the helper), `TrustDecisionPort` (macOS
trust), and `TrustProbing` (the system HTTPS check, with the live `SystemTrustProbe`).

## Rules

- Detection reads file metadata only. Jerd never runs project code to detect a project.
- Caddy gets JSON only: admin API off, internal CA only, `install_trust: false`, loopback or
  inherited listeners only, strict SNI, 421 for unknown hosts, 308 from HTTP to HTTPS.
- Dot paths, private folders, Composer files, and PHP-like names answer 404. An existing file
  below `/.well-known/` is served statically; hidden files there still answer 404.
- PHP and FPM end a request after 30 seconds. Caddy waits 35 seconds, so PHP decides.
- Caddy and PHP-FPM never run as root. Each run has a new private socket folder. The engine
  removes only a folder that it created, and deletes a run record only for a proven stop.
- Readiness uses CA-verified HTTPS with the run's CA. Never `curl -k`.
- A Stop raises a stop epoch. Every step of an older operation ends with `CancellationError`.
- Only `SiteChangeTransaction` rolls back. A failure restores the settings, the HTTPS setup,
  and the previous run once, and reports once.
- An approval covers every registered hostname. Removed or renamed hostnames leave the set.
- Ports 80 and 443 are checked once, right before the helper leases them.
- Corrupt configuration and identity files stay in place. Load and save then fail.

## Files

All paths come from `DataLayout`. Each PHP runtime has its own pool folder
`environment/php/<runtime UUID>/` (configuration and log). Caddy uses
`environment/configuration/caddy.json` and `environment/logs/caddy.log`.

## For the CLI target

Use `ConfigurationCodec.store(in:)` to read the configuration, `PHPIniPolicy.cliFile(caBundle:)`
for the CLI INI, and `PHPCABundleBuilder.prepareForCLI(layout:)` for the CA bundle.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdWebTests
```

The default tests use temporary folders, fakes, and loopback ports above 1023. Opt-in tests
need `JERD_INTEGRATION=1`, `JERD_PHP_CLI`, `JERD_PHP_FPM`, and `JERD_CADDY` (and optionally
`JERD_SECOND_PHP_CLI` and `JERD_SECOND_PHP_FPM`). They use an isolated CA and change no
system trust.
