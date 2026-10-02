# Jerd

Jerd is a native macOS app for local PHP development. It serves registered
`.test` sites over HTTPS, with a selected PHP version for each site.
It also manages MySQL, PostgreSQL, Redis, RustFS storage, and a Mailpit inbox.
Each data service uses private files and loopback ports.

The Dashboard contains service status, appearance controls, runtime versions,
and app update controls. Sparkle checks the signed app feed on GitHub.
PHP, Composer, and Laravel commands can use the current project's PHP selection.

## Requirements

The app targets macOS 14 or later and requires Xcode with Swift 6 to build.
The prepared runtime files have been tested on Apple Silicon with macOS 27.0.1,
Xcode 27.0, and Swift 6.4. Intel and macOS 14 execution remain unverified.
HTTPS setup requires an Apple signing identity and approval from the user.
Ports 80 and 443 must be available on `127.0.0.1`.

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
