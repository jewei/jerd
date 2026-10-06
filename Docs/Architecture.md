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
| `JerdLive` | Live implementations of the UI ports, the composition of the live domain, and the launch steps |
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
and the release publisher of `./dev release`.

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
processes that survive an app crash. After a crash, Start reads the record
before it checks the port, so it names Process recovery, not "port occupied".

Caddy and PHP-FPM hold no user data, so their stop is forceful (a bounded
`SIGKILL` of the group). If a process still runs after that, the engine keeps
the run, its records, and the environment lock, the state is Failed, and the
next Stop retries. Quit does not wait for it; the kept record
makes the next launch name Process recovery.

## Live wiring and app startup

`Apps/Jerd` holds only the scenes (`JerdApp`), the app delegate, and the Sparkle adapter.
`JerdLive.LiveApp` builds every port on the real domain and the root `AppState`; building it
changes nothing on disk.

Startup does not depend on a window:

1. `applicationWillFinishLaunching` applies the Dock and icon choices, so a hidden Dock icon
   never flashes.
2. `applicationDidFinishLaunching` starts `LiveApp.launch()`:
   1. Removes abandoned runtime staging folders and refreshes an outdated command-line
      launcher, off the main actor.
   2. `AppState.launch()` starts the updater, then launches each feature in section order.
      Sites loads the site configuration and installs the bundled PHP and Caddy when they are
      missing; Databases, Storage, and Mail each load their settings and install their bundled
      runtimes when none is registered; Tunnels connect the tunnels marked "Start when Jerd
      opens". Then Runtimes and Advanced load, and polling starts.
3. Reopening Jerd (Dock or Applications) shows the main window, also when the menu bar item and
   the Dock icon are both off.

Quit runs the staged quit of `AppState` (`ShutdownCoordinator`): runtime work, tunnels,
storage, mail, databases, then the web environment. `applicationShouldTerminate` answers
`.terminateLater` once and replies once; a second request during a quit is cancelled at once.
A service that does not stop cancels the quit and keeps Jerd open. Sparkle uses the same path.

A Debug build reads `JERD_DEBUG_DATA_ROOT` to run with an empty data folder. Release builds
always use `~/Library/Application Support/Jerd`.

## Data

All user data is under `~/Library/Application Support/Jerd`. `DataLayout` in
`JerdFoundation` names every path. The helper keeps its records under
`/Library/Application Support/JerdHelper`. See [Data reference](Reference.md).
