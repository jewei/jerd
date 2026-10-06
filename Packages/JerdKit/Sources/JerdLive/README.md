# JerdLive

JerdLive implements every port of JerdUI with the real domain and AppKit, and builds the app
state that the app target shows. It keeps no policy: each adapter maps values and forwards
calls. Pure mappings are `package static` functions with their own tests.

## Structure

| Folder | Contents |
| --- | --- |
| `Composition/` | `LiveConfiguration` (bundle, data root, version), `LiveDomain` (one owner per file and process), `WebDomain`, `LiveApp` (all ports, the root state, and the launch), `LaunchPreparation`. |
| `Sites/` | `LiveSitesPort`, the helper adapter `HelperSystemSetup` (JerdWeb `SystemSetupPort`), `HelperStatusMapping`, the bundled PHP and Caddy setup (`DevelopmentRuntimeSetup`), `SiteChangeStep`, Login Items. |
| `Tunnels/` | `LiveTunnelsPort` on `TunnelSupervisor`. |
| `Services/` | `LiveDatabasesPort`, `LiveMailPort`, `LiveStoragePort`, and the bundled service runtimes. |
| `Settings/` | Runtimes (`LiveRuntimeInventory`, `RuntimeActivator`), Advanced (`LiveRecoveryPort`, `LiveExecutableRegistrations`, `LiveHTTPSRecovery`), and `LiveCommandLineTools`. |
| `AppKit/` | Dock and icon (`AppPresence`, `AppIconImages`), the app and window activity for the polling rates (`AppActivityMonitor`), the main window, pasteboard, Finder, open panels, the quit paths that end open sheets first (`ApplicationQuit`, `QuitAppleEventHandler`), the termination reply, and the pure Sparkle rules (`UpdateCycleMapping`). |

## Wiring rules

- One graceful `ProcessSupervisor` runs every data service and tunnel connector. The web engine
  keeps the JerdWeb default, `ProcessSupervisor(ceiling: .forceful)`, because Caddy and PHP-FPM
  hold no user data.
- Every site edit, Start, Stop, and PHP or Caddy record change goes through the one
  `SiteChangeTransaction`. A change that needs HTTPS approval waits in `LiveSitesPort` under its
  `HTTPSApproval.id`. Approve registers the helper first, then continues the change; a failure
  keeps the change for a retry. Discard forgets it.
- `HelperStatusMapping` maps the helper status to the web status. A pending recovery sets
  `hasPendingRecovery`. A running helper transaction (`operationInProgress`) throws, because it
  is neither "no setup" nor "interrupted".
- The PHP CA bundle trusts the local CA only while macOS trusts it (`SystemTrustDecision`).
- Each feature load installs its bundled runtimes before it reads its services: PHP and Caddy
  in the first site load (`DevelopmentRuntimeSetup`, shared with Advanced), the database
  engines without a runtime, Mailpit and RustFS when none is saved. A corrupt settings file
  fails the load before anything is installed. A failed bundled setup does not fail the load:
  the site setup message shows it in Advanced. The service setups write it to the unified log
  (`subsystem == "dev.jerd.app"`) and keep its reason in a `BundledSetupRecord`, which the
  port reports through `runtimeSetupFailure()`; the service page shows it in its missing-runtime
  banner. A later successful setup clears it.
- The Tunnels model calls `connectStartupTunnels()` after a successful `load()`. `stopAll()`
  throws while a connector still runs, so Quit is cancelled.
- At launch, before the features load: abandoned staging folders are removed, and an outdated
  command-line launcher is refreshed once, off the main actor
  (`LiveConfiguration.refreshesCommandLineLauncher`). A run with another data root never
  touches the user's launcher, and keeps Jerd's preferences in its own defaults domain
  (`LiveConfiguration.defaultsSuiteName`), never in the user's `dev.jerd.app`. AppKit still
  saves the window frame in the standard domain.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdLiveTests
```

Every adapter depends on a small role protocol (`HelperControlling`, `SiteChangeApplying`,
`DatabaseManaging`, `TunnelControlling`, …) that the domain type conforms to here. The tests
use recording fakes: no helper, no network, no process, and only temporary folders.
