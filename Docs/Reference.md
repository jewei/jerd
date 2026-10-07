# Data reference

Jerd keeps user data in `~/Library/Application Support/Jerd` (the data root,
mode 0700). The helper keeps its records in `/Library/Application Support/JerdHelper`.
`DataLayout` in `JerdFoundation` names every path below. Each path is part of the
compatibility contract with installed copies. Do not change a path without a
migration and a test that reads the old form. `DataReferenceTests` checks that
this page names every path of `DataLayout`.

`<UUID>` is an uppercase UUID. Files are private (mode 0600) and folders are
private (mode 0700).

## Top level and web environment

| Path | Contents |
| --- | --- |
| `configuration.json` | Sites and PHP runtimes (pretty, sorted keys) |
| `configuration.previous.json` | The bytes of `configuration.json` before the last save |
| `bin` | The optional `php`, `composer`, and `laravel` launcher links |
| `shell-backups` | Shell file backups, one folder per change |
| `environment/installation-id` | The installation ID: an uppercase UUID without a newline |
| `environment/configuration/caddy.json` | The Caddy configuration |
| `environment/configuration/prepare-ca.json` | The Caddy configuration that creates the installation CA |
| `environment/configuration/php-ca.pem` | The CA bundle of PHP-FPM |
| `environment/configuration/empty-ini` | An empty `PHP_INI_SCAN_DIR` |
| `environment/configuration/php-fpm.conf` | Legacy layout only: the first pool of old builds. Removed when Jerd wrote it |
| `environment/configuration/php.ini` | Legacy layout only: the `php.ini` of that pool. Removed when Jerd wrote it |
| `environment/certificates/pki/authorities/jerd/root.crt` | The installation CA certificate (Caddy storage) |
| `environment/logs/caddy.log` | The Caddy log |
| `environment/logs/fpm.log` | Legacy layout only: the log of the old first pool. Removed |
| `environment/php/<UUID>` | The FPM pool of one PHP runtime: `configuration/php-fpm.conf`, `configuration/php.ini`, `logs/fpm.log` |
| `environment/preflight-<UUID>` | A transient preflight folder, deleted after use |
| `environment/processes/<UUID>.json` | The run record of one web process |
| `environment/processes/recovery.lock` | The lock of the web run records |

## Runtimes

| Path | Contents |
| --- | --- |
| `runtimes` | Bundled development payloads, one folder per payload |
| `runtimes/cli-tools.json` | The selected Composer and Laravel installer |
| `runtimes/configuration/cli.ini` | The `php.ini` of the `php` command |
| `runtimes/configuration/cli-local-tls.ini` | The local TLS settings of the `php` command |
| `runtimes/configuration/php-ca.pem` | The CA bundle of the `php` command |
| `runtimes/configuration/empty-ini` | An empty `PHP_INI_SCAN_DIR` for the `php` command |
| `runtimes/inspection/empty-ini` | The PHP inspection folder during a payload installation |
| `runtime-inspection/empty-ini` | The PHP inspection folder during activation and import |
| `runtime-updates` | Managed runtime builds, also the database engines that Jerd installs on demand (`<kind>-<release>-arm64-<archive SHA-256>/` with `update-receipt.json`) |
| `database-runtimes` | Database payloads that earlier versions installed from the app bundle. They stay in use; Jerd never removes them |
| `mail-runtimes` | Installed Mailpit payloads |
| `storage-runtimes` | Installed RustFS payloads |

## Databases

| Path | Contents |
| --- | --- |
| `databases/services.json` | The database registry (pretty, sorted keys) |
| `databases/services.previous.json` | The registry before the last save |
| `databases/instances/<UUID>/service.lock` | The lock of the instance |
| `databases/instances/<UUID>/active-run.json` | The run record of the server |
| `databases/instances/<UUID>/runtime.json` | The runtime identity that owns the data |
| `databases/instances/<UUID>/initialized.json` | The marker of completed initialization |
| `databases/instances/<UUID>/credentials.json` | The generated password |
| `databases/instances/<UUID>/removed-registration.json` | The registration kept after Remove, for Restore |
| `databases/instances/<UUID>/server.log` | The server output |
| `databases/instances/<UUID>/server.previous.log` | The output of the previous run |
| `databases/instances/<UUID>/data` | The database files |

## Mail

| Path | Contents |
| --- | --- |
| `mail/settings.json` | Mail settings |
| `mail/settings.previous.json` | The settings before the last save |
| `mail/service.lock` | The lock of the mail service |
| `mail/active-run.json` | The run record of Mailpit |
| `mail/server.log` | The Mailpit output |
| `mail/server.previous.log` | The output of the previous run |
| `mail/inbox/messages.sqlite` | Captured mail |
| `mail/inbox/runtime.json` | The runtime identity that owns the inbox |
| `mail/inbox/initialized.json` | The marker of completed initialization |
| `mail/runtime-update.json` | The journal of an unfinished runtime update |
| `mail/runtime-backups` | Copies made before runtime updates |

## Storage

| Path | Contents |
| --- | --- |
| `storage/settings.json` | Storage settings |
| `storage/settings.previous.json` | The settings before the last save |
| `storage/service.lock` | The lock of the storage service |
| `storage/active-run.json` | The run record of RustFS |
| `storage/server.log` | The RustFS output |
| `storage/server.previous.log` | The output of the previous run |
| `storage/runtime.json` | The runtime identity that owns the data |
| `storage/initialized.json` | The marker of completed initialization |
| `storage/credentials.json` | The credentials; its exact bytes are hashed in `initialized.json` |
| `storage/access-key` | The access key, without a newline |
| `storage/secret-key` | The secret key, without a newline |
| `storage/data` | Buckets and objects |
| `storage/data/.rustfs.sys/format.json` | The RustFS volume format |
| `storage/runtime-update.json` | The journal of an unfinished runtime update |
| `storage/runtime-backups` | Copies made before runtime updates |

## Tunnels

| Path | Contents |
| --- | --- |
| `tunnels/settings.json` | Tunnel registrations (no token) |
| `tunnels/settings.previous.json` | The registrations before the last save |
| `tunnels/instances/<UUID>/service.lock` | The lock of the connector |
| `tunnels/instances/<UUID>/active-run.json` | The run record of cloudflared |
| `tunnels/instances/<UUID>/config.yml` | The empty cloudflared configuration (`{}`) |
| `tunnels/instances/<UUID>/server.log` | The output of the current connector run |
| `tunnels/instances/<UUID>/server.previous.log` | The output of earlier runs (at most 4 MiB) |
| `tunnels/instances/<UUID>/home` | The private `HOME` of cloudflared |

## Locks

Every lock is an exclusive, non-blocking `flock` on a private file. Old and new
builds use the same lock files, so they exclude each other during an upgrade.
A run record is written or deleted only while its lock is held.

## Helper records

The helper keeps these files in `/Library/Application Support/JerdHelper`. The
folder has mode 0700 and the owner root. `RootRecordDirectory` in JerdSystem is
their one reader and writer. `HelperRecordReferenceTests` checks this list.

| File | Contents |
| --- | --- |
| `registration.json` | The committed setup: hostnames, the CA, and its trust. Versions 1 to 3 are read; version 3 is written |
| `pending.json` | The journal of an unfinished setup change, for recovery |
| `hosts.previous` | The hosts file bytes before the latest change (evidence only) |
| `recovery.previous.json` | The journal bytes from the first recovery attempt of a change |

The helper edits only the lines between `# BEGIN JERD` and `# END JERD` in
`/etc/hosts`.

## Defaults

The app keeps these keys in the `dev.jerd.app` defaults domain.
`AppearanceDefaults` in JerdUI is their one reader and writer.
`AppearanceDefaultsReferenceTests` checks this list.

| Key | Value |
| --- | --- |
| `showMenuBar` | Bool. Show the menu bar item. Missing means true |
| `showDock` | Bool. Show the Dock icon. Missing means true |
| `appIcon` | String: `rainbow`, `monogram`, `elephant`, or `dots`. Old values (`original`, `stack`, `lock`), unknown values, and a missing value read as `rainbow` without a rewrite |

Sparkle keeps its own `SU…` keys in the same domain, for example the choice of
automatic update checks. Jerd does not write them directly.

A Debug run with another data root uses the domain
`dev.jerd.app.debug.<16 hex digits>`, so it never changes these choices.

## Keychain

| Item | Name |
| --- | --- |
| Tunnel token | Generic password, service `dev.jerd.cloudflared.tunnel-token`, account = the registration UUID in upper case. `TunnelKeychainReferenceTests` checks the service |
| Installation CA | Certificate `Jerd Local CA <installation ID>` in the System keychain, with admin trust settings for TLS. The helper adds and removes it |
