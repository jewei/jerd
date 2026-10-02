# Data and components

## Source components

The source separates the SwiftUI app, shared core logic, and privileged helper.

| Component | Responsibility |
| --- | --- |
| `Models`, `Sites`, `SiteRegistry`, `Persistence` | Validation, hostname suggestions, runtime selections, serialized atomic storage |
| `Runtimes`, `BundledRuntimes` | Actual binary inspection; verified app-owned development payload installation |
| `Configuration`, `Processes`, `ServingEngine` | Caddy/FPM configuration; owned process groups; startup, TLS checks, and cleanup |
| `LocalEnvironment` | All enabled sites; stable CA identity; normal macOS HTTPS trust check for every hostname |
| `HelperClient`, `SystemIntegration` | SMAppService registration and typed authenticated XPC |
| `HelperService`, `ListeningSockets` | Exclusive loopback socket lease per client; descriptor transfer |
| `PrivilegedSetupStore`, `AtomicHostsFile`, `HostsDocument` | Owned host section, certificate ownership, rollback, and recovery records |
| `SystemCertificateTrust`, `CertificateTrustSettings` | System keychain and explicit TLS trust policies through Security.framework |
| `TrustConsentClient`, `TrustConsentService`, `TrustConsentScope` | App-side macOS consent for the exact approved certificate, setup hosts, and trust policy |
| `JerdCLI`, `CLIRuntimeSelection` | Project-aware PHP selection and direct execution of PHP/Composer/Laravel |
| `DatabaseModel`, `DatabaseServicesView` | Database list, connection details, and independent service controls |
| `DatabaseManager`, `DatabaseDriver` | Data initialization, engine arguments, readiness, owned processes, and graceful stop |
| `MailManager`, `MailDriver`, `MailStore` | Independent Mailpit inbox, SMTP/HTTP checks, persistent settings, and graceful stop |
| `LocalServicePorts` | Shared wildcard-port detection and exact listener ownership checks for data services |
| `DatabaseStore`, `BundledDatabaseRuntimes` | Separate versioned service records and verified native runtime installation |
| `StorageManager`, `StorageS3Client` | RustFS lifecycle, signed S3 requests, and bucket checks |
| `RuntimeUpdateCatalog`, `RuntimeInstaller` | Release lookup, bounded downloads, verification, and runtime installation |
| `AppUpdatesModel`, `AppUpdateConfiguration` | Sparkle lifecycle, app update preferences, and bundled feed validation |


## Data paths

The following paths are relative to `~/Library/Application Support/Jerd`, unless
an absolute path is shown. This table lists the main persisted records.

| Path | Contents |
| --- | --- |
| `configuration.json`, `configuration.previous.json` | Site records and PHP/Caddy selections |
| `runtimes/` | PHP/Caddy binaries, receipts, licenses, and `cli-tools.json` |
| `bin/`, `shell-backups/` | Optional CLI launcher, command links, and shell backups |
| `database-runtimes/` | Database binaries, libraries, receipts, and notices |
| `databases/services.json` | Database service and runtime records; a previous copy is retained |
| `databases/instances/<UUID>/` | Database files, credentials, runtime identity, initialization marker, log, and active process record |
| `mail-runtimes/`, `mail/` | Mailpit runtimes, settings, log, active process record, and SQLite inbox |
| `storage-runtimes/`, `storage/` | RustFS runtimes, settings, credentials, log, active process record, and object data |
| `mail/runtime-backups/`, `storage/runtime-backups/` | Data and settings saved before runtime changes |
| `environment/installation-id` | Stable identity for the installation CA |
| `environment/configuration/` | Generated Caddy, FPM, and PHP settings |
| `environment/certificates/` | Private CA keys and issued certificates |
| `environment/logs/` | Web environment output |
| `/Library/Application Support/JerdHelper/registration.json` | Owner UID, hostnames, installation ID, CA certificate, and trust policy |
| `/Library/Application Support/JerdHelper/hosts.previous` | Host-file backup for a system transaction |
| `/Library/Application Support/JerdHelper/pending.json` | Incomplete system transaction record |

FPM sockets use a new private temporary directory for each run.
Preferences use the `dev.jerd.app` UserDefaults domain.
The Sparkle signing key uses the `dev.jerd.sparkle` account in the local Keychain.
The repository contains only its public key.

## Data preservation and recovery limits

Configuration writes are atomic and retain a valid backup. Corrupt records block
changes and remain available for inspection. Jerd does not reset them to empty records.
Database removal retains the instance directory and credentials.
Stop and Quit retain database, mail, and storage data.

Database startup rejects a different runtime identity, incomplete initialization,
missing credentials, and an instance already in use. Mail and storage enforce
corresponding checks for their initialized data and saved credentials.
A previous live process blocks startup. Jerd does not signal saved PIDs that it
did not create in the current session. Automatic process recovery is incomplete.

A remaining helper `pending.json` blocks further system changes.
The hosts backup may precede later external edits, so replacing the whole current
hosts file with that backup can discard unrelated changes.
Automated helper transaction recovery and a database restore-registration action
are not implemented. Logs do not rotate automatically.

For the reasons behind these limits, see [Architecture](Architecture.md).
