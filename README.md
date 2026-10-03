# Jerd

Jerd is a native macOS app for local PHP development. It serves registered
`.test` sites over HTTPS, with a selected PHP version for each site.
It also manages MySQL, PostgreSQL, Redis, RustFS storage, and a Mailpit inbox.
Each data service uses private files and loopback ports.
The Sites tab can manage connectors for existing Cloudflare Tunnels.

The Dashboard contains service status, appearance controls, runtime versions,
and app update controls. Sparkle checks the signed app feed on GitHub.
PHP, Composer, and Laravel commands can use the current project's PHP selection.

## Requirements

The app targets macOS 14 or later and requires Xcode with Swift 6 to build.
The prepared runtime files have been tested on Apple Silicon with macOS 27.0.1,
Xcode 27.0, and Swift 6.4. Intel and macOS 14 execution remain unverified.
HTTPS setup requires an Apple signing identity and approval from the user.
Ports 80 and 443 must be available on `127.0.0.1`.

## Repository layout

| Folder | Contents |
| --- | --- |
| `Sources/` | App, CLI, and helper targets; app code is grouped by feature |
| `Packages/JerdCore/` | Shared Swift code and tests; code is grouped by service and responsibility |
| `Runtimes/` | Runtime version pins, the Laravel installer lock file, and release support pins |
| `Scripts/` | Runtime preparation, release tools, development tools, checks, and script tests |
| `Design/` | App icon designs |
| `Docs/` | Build, use, test, and release instructions |

`project.yml` defines the Xcode project. Generated builds and private release
candidates are in the ignored `.build/` folder. `Scripts/release.sh` is the
release entry point. The published feed remains at `appcast.xml`.

## Documentation

The documentation covers these tasks and reference topics.

| Document | Contents |
| --- | --- |
| [Build Jerd](Docs/Build.md) | Runtime preparation and local builds |
| [Use Jerd](Docs/UseJerd.md) | Sites, data services, settings, and updates |
| [Run tests](Docs/Testing.md) | Core tests, isolated service tests, and system checks |
| [Publish an app update](Docs/PublishUpdate.md) | Signing, notarization, release archives, and the app feed |
| [Data and components](Docs/Reference.md) | Source modules, data paths, and recovery limits |
| [Architecture](Docs/Architecture.md) | Process ownership, system permissions, and update design |
| [Verification record](Docs/Verification.md) | Completed checks and known test gaps |
| [Implementation status](Docs/ImplementationPlan.md) | Completed features and remaining work |

This is a development build. No notarized Jerd release has been published.
The signed app feed is empty until the first update archive is published.
