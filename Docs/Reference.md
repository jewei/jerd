# Data and components

## Source components

The source separates the SwiftUI app, shared core logic, and privileged helper.

`Sources/Jerd/` contains `Application`, `Features`, `SystemIntegration`, and
`Resources`. `Sources/JerdCLI/` and `Sources/JerdHelper/` contain the other app
targets. The Swift package keeps its normal `Sources` and `Tests` layout.
Within `Packages/JerdCore/Sources/JerdCore/`, code is grouped into `Common`,
`Web`, `Runtimes`, `Services`, and `SystemIntegration`.

`Runtimes/` stores repository inputs for Development, Database, Mail, Storage,
and Support. `Scripts/` groups tools under `Runtimes`, `Release`, `Checks`,
`Development`, and `Tests`. App bundle resource names and installed data paths
are separate from these repository paths.

| Component | Responsibility |
| --- | --- |
| `Models`, `Sites`, `SiteRegistry`, `Persistence` | Validation, hostname suggestions, runtime selections, serialized atomic storage |
| `Runtimes`, `BundledRuntimes` | Actual binary inspection; verified app-owned development payload installation |
| `Configuration`, `Processes`, `ServingEngine` | Caddy/FPM configuration; owned process groups; startup, TLS checks, and cleanup |
| `SiteConfigurationOperation` | Candidate preparation, approval, persistence, activation, and rollback |
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
| `environment/logs/` | Bounded web environment output |
| `environment/processes/` | Verified process identities for web recovery |
| `runtimes/configuration/` | Generated CLI INI and empty INI scan directory |
| `runtime-updates/<kind>-<version>-<architecture>-<SHA256>/` | Separate verified runtime builds |
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
Database removal retains the instance directory, credentials, and removed registration metadata.
The Databases restore action requires the original runtime identity.
Stop and Quit retain database, mail, and storage data.

Database startup rejects a different runtime identity, incomplete initialization,
missing credentials, and an instance already in use. Mail and storage enforce
corresponding checks for their initialized data and saved credentials.
A surviving process blocks startup until it stops safely. Advanced can inspect and
recover saved processes with verified boot/start identity, executable, UID, and
kernel audit token. PID reuse clears a stale record without signalling its new
owner. Missing audit support, legacy records, and uncertain child ownership need
manual inspection. Normal Quit still stops owned services.

The helper's `pending.json` records an interrupted operation and its last known
stage. Advanced offers approved restore or removal when the evidence permits it.
Recovery modifies only the tracked host section and preserves unrelated current
entries. It retains the original journal and host backup for inspection.

While Jerd runs, process output above 8 MiB is trimmed once per second to the
latest 4 MiB. A write burst can exceed the threshold between checks. Command
logs also retain the first 1 MiB for parsers. Live trimming keeps the same file
inode; a concurrent write can be lost or reordered at that boundary. These are
diagnostic logs, not service data. Stopping a process also trims its log. An
orphan process can keep writing while Jerd is closed; inspect it in Advanced.

Mail and storage runtime backups remain until explicit deletion. Advanced shows
size and purpose. A pending recovery journal, including a corrupt journal,
protects every backup for that service. Cleanup takes the service lock and
rejects a saved live process. It never deletes current service data.

For the reasons behind these limits, see [Architecture](Architecture.md).
