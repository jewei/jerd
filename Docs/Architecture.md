# Architecture

Jerd is a macOS app, a privileged helper, and a command-line launcher. Almost
all code is in the `JerdKit` Swift package. The three app targets in `Apps/`
contain only entry points, resources, and live wiring.

## Layers

```
Apps/Jerd ─────────► JerdLive ──► JerdUI ──► JerdDesign, domain value types
Apps/JerdHelper ───► JerdHelperCore ──► JerdSystem
Apps/JerdCLI ──────► JerdCLICore ──► JerdWeb, JerdRuntimes

Domain:      JerdWeb   JerdSystem   JerdRuntimes   JerdDatabases JerdMail JerdStorage JerdTunnels
                                                    └──────────── JerdServiceKit ────┘
Base:        JerdProcess   JerdManifest   JerdArchive (CArchive)
             └────────────── JerdFoundation ──────────────┘
```

A target may import only the targets that `Package.swift` lists for it.
`Package.swift` lets `JerdUI` import the domain targets, so that screens can show
their value types. `JerdUI` calls side effects only through its own port
protocols, which `JerdLive` implements. The compiler does not enforce this
rule; review does.
Domain targets do not import each other, except the service modules, which use
`JerdServiceKit`. When a domain target needs another domain, it declares a
small port protocol with its own value types. `JerdLive` implements the port
with the other domain. This keeps each target buildable, testable, and
reviewable alone.

## Targets

The table describes the target design of the rewrite. A target whose folder
holds only `Placeholder.swift` is not built yet.

| Target | Responsibility |
| --- | --- |
| `JerdFoundation` | `JerdError`, safe private files, atomic writes, instance locks, versioned JSON documents, the data layout, `.test` hostnames, secrets, digests, safe relative paths |
| `JerdProcess` | Spawn plans and `posix_spawn`, the process supervisor, stop policies, process-group inspection, bounded and redacted logs, one-shot commands, process identity, saved run records, recovery classification, and loopback listener inspection |
| `JerdManifest` | Runtime pins, payload receipts, build receipts, payload folder IDs, app update settings, and appcast signature checks; shared with `Tools/` |
| `JerdArchive` | libarchive reading, pure extraction plans, and bounded extraction |
| `JerdRuntimes` | Runtime versions and kinds, release catalogs, HTTPS fetches, checksum and OpenPGP checks, runtime preparation, version probes, managed runtime installation, bundled payload installation, CLI companion selections |
| `JerdSystem` | The helper XPC protocol and DTOs, hosts sections, guarded file swaps, helper records, setup transactions, recovery assessment, trust policies, certificate identity, consent scope, code-signing requirements, reply gates, port leases, and the app-side helper client |
| `JerdHelperCore` | Helper daemon logic: connection acceptance, system keychain certificates, trust installation, consent requests, and the XPC service |
| `JerdWeb` | Site configuration and its codec, project detection, site validation, the site registry, serving plans, Caddy, FPM, and PHP INI rendering, the installation CA, PHP CA bundles, FastCGI ping, the serving engine, readiness checks, the environment coordinator, and the site change transaction |
| `JerdCLICore` | CLI runtime selection, launch plans, the shell PATH block, and shell setup |
| `JerdServiceKit` | The managed-instance state machine shared by databases, mail, and storage; data identity guards, readiness polling, runtime update transactions, and backup retention |
| `JerdDatabases` | MySQL, PostgreSQL, and Redis definitions, the service registry, retained registrations, and the database manager |
| `JerdMail` | The Mailpit definition, mail settings, test messages, and the mail manager |
| `JerdStorage` | The RustFS definition, the S3 signer, transport, and parsers, bucket policies, bucket provisioning, and the storage manager |
| `JerdTunnels` | Tunnel tokens, the Keychain secret store, the cloudflared connector, the reconnect policy, and the tunnel supervisor |
| `JerdDesign` | Design tokens and reusable SwiftUI components |
| `JerdUI` | Navigation, feature view models, screens, and the port protocols that the UI needs |
| `JerdLive` | Live implementations of the UI ports, app bootstrap, and the staged shutdown |
| `JerdUIFixtures` | In-memory port implementations and sample data for previews, tests, and snapshots |
| `JerdSnapshotSupport` | Offscreen snapshot rendering, the snapshot catalog, and the component gallery; never linked into the app |
| `JerdSnapshots` | Renders every page with fixtures to PNG files |

## Patterns

**Pure policy, effectful shell.** Rules are pure values and functions with
table tests: hostname rules, route rendering, recovery classification, the
reconnect policy, and release filters. Actors perform file, process, and
network work and call the pure rules.

**Ports.** A protocol describes each side effect: commands, the helper,
the clock, HTTP fetches, the keychain. Live types use the system. Tests use
fakes. View models depend only on ports.

**Explicit state machines.** Every long-running component has a named state
enum and one function that changes it: managed instances, the environment
coordinator, the site change transaction, the setup transaction, tunnels,
and the release publisher of the planned `./dev release` command.

**One owner per file.** Each saved file has exactly one type that reads and
writes it. That type keeps the exact compatible encoding and the backup copy.

**Errors.** `JerdError` carries a kind and a user message. A view shows the
message of the operation that failed, once, on the page that owns it.

## Process model

PHP-FPM, Caddy, and all data services run as the user, in their own process
groups, with a clean environment and only the file descriptors that they need.
The helper runs as root, binds only `127.0.0.1:80` and `127.0.0.1:443`, edits
only Jerd's tracked hosts section, and manages only Jerd's installation CA.
It never starts a process.

Data services stop with a graceful signal and a 30-second limit. A timeout
never escalates to `SIGKILL`; the process, its record, and its data lock stay,
and Quit is cancelled. Saved run records let Jerd find and safely stop
processes that survive an app crash.

## Data

All user data is under `~/Library/Application Support/Jerd`. `DataLayout` in
`JerdFoundation` names every path. The helper keeps its records under
`/Library/Application Support/JerdHelper`. See [Data reference](Reference.md).
