# JerdLive

JerdLive implements every port of JerdUI with the real domain and AppKit, and builds the app
state that the app target shows. It keeps no policy: each adapter maps values and forwards
calls. Pure mappings are `package static` functions with their own tests.

## Structure

| Folder | Contents |
| --- | --- |
| `Composition/` | `LiveConfiguration` (bundle, data root, version), `LiveDomain` (one owner per file and process), `WebDomain`, `LiveApp` (all ports, the root state, and the launch), `LaunchPreparation`. |
| `Sites/` | `LiveSitesPort`, the helper adapter `HelperSystemSetup` (JerdWeb `SystemSetupPort`), `HelperStatusMapping`, the bundled PHP and Caddy setup (`DevelopmentRuntimeSetup`), `SiteChangeStep`, Login Items. |
| `Tunnels/` | `LiveTunnelsPort` on `TunnelSupervisor`. `LiveTunnelSiteResolver` (JerdTunnels `TunnelSiteResolving`) on the site change transaction, and `LiveForwardedHosts` (JerdWeb `ForwardedHostsLoading`) on `TunnelSiteRoutes`. |
| `Services/` | `LiveDatabasesPort`, `LiveMailPort`, `LiveStoragePort`, and the bundled service runtimes. |
| `Settings/` | Runtimes (`LiveRuntimeInventory`, `RuntimeActivator`), Advanced (`LiveRecoveryPort`, `LiveExecutableRegistrations`, `LiveHTTPSRecovery`), and `LiveCommandLineTools`. |
| `Workspace/` | The main window split (`WorkspaceSplit`, `WorkspaceSplitController`). The sidebar is a plain split item, because AppKit lays out the whole toolbar after a `.sidebar` item with a sibling and the picker then moved. The plain item holds `WorkspaceSidebarController`: a split with one `.sidebar` item and no sibling, so AppKit draws the system sidebar background (from macOS 26 a glass variant without public API; an `NSVisualEffectView` with the `.sidebar` material is lighter). The split makes the title bar transparent, because a window with a `.sidebar` item draws a title bar band over the sidebar top. `SidebarWidthLimit` (JerdDesign) keeps the sidebar edge left of the centered picker in a narrow window. |
| `AppKit/` | Dock and icon (`AppPresence`, `AppIconImages`). The app and window activity for the polling rates (`AppActivityMonitor`). The main window, pasteboard, Finder, and open panels. The quit paths that end open sheets first (`ApplicationQuit`, `QuitAppleEventHandler`), and the termination reply. The pure Sparkle rules (`UpdateCycleMapping`). |

## Wiring rules

- One graceful `ProcessSupervisor` runs every data service and tunnel connector. The web engine
  keeps the JerdWeb default, `ProcessSupervisor(ceiling: .forceful)`, because Caddy and PHP-FPM
  hold no user data.
- Every site edit, Start, Stop, PHP or Caddy record change, and forwarded host apply of a local
  tunnel goes through the one `SiteChangeTransaction`. A change that needs HTTPS approval waits in `LiveSitesPort` under its
  `HTTPSApproval.id`. Approve registers the helper first, then continues the change; a failure
  keeps the change for a retry. Discard forgets it.
- `HelperStatusMapping` maps the helper status to the web status. A pending recovery sets
  `hasPendingRecovery`. A running helper transaction (`operationInProgress`) throws, because it
  is neither "no setup" nor "interrupted".
- The PHP CA bundle trusts the local CA only while macOS trusts it (`SystemTrustDecision`).
- Each feature load installs its bundled runtimes before it reads its services: PHP and Caddy
  in the first site load (`DevelopmentRuntimeSetup`, shared with Advanced), the database
  engines without a runtime, an embedded Mailpit and an embedded RustFS when none is saved.
  Mailpit and RustFS are not embedded, so the mail and storage loads install nothing and record
  no failure; a saved runtime (also one in `mail-runtimes/` or `storage-runtimes/`) stays in use. A corrupt settings file
  fails the load before anything is installed. A failed bundled setup does not fail the load:
  the site setup message shows it in Advanced. The service setups write it to the unified log
  (`subsystem == "dev.jerd.app"`) and keep its reason in a `BundledSetupRecord`. The port
  reports it through `runtimeSetupFailure()`, and the service page shows it in its
  missing-runtime banner. A later successful setup clears it.
- `LiveDomain` has one `URLSessionFetcher` and one `RuntimeInstaller`. The Runtimes page and the
  on-demand database installation share them. Both pages install a pinned database engine through
  one flow (`OnDemandInstallFlow`, used by `DatabaseRuntimeInstaller` in `LiveDatabasesPort` and in
  `LiveRuntimeInventory`): a verified earlier payload is reused; an installed build of the pin in
  `runtime-updates/` is reused; only a real download first checks the free space
  (`FreeSpaceReading`). The dialogs say "Nothing is downloaded" when a copy is reused. One
  installation runs at a time. `DatabaseRuntimeInstaller` takes the pinned release from
  `OnDemandRuntimes` (the catalog in the bundle), installs it, and registers the build with the
  database manager. The launch never calls it: only Install and Add Database do. The Runtimes
  snapshot lists the same pins (`onDemand`), so Runtimes offers them too.
- `StorageRuntimeInstaller` (in `LiveStoragePort` and `LiveRuntimeInventory`) installs the pinned
  RustFS through the same `OnDemandInstallFlow`. The preparation gets the XZ library of the app
  (`LZMAProviding`, the bootstrap); without it the install stops before the download. It
  registers the runtime with `StorageManager.registerRuntime`, which never replaces a saved
  runtime and never touches buckets, objects, or credentials. Only Install RustFS…, Start, and
  Runtimes › Install… call it.
- `MailRuntimeInstaller` (in `LiveMailPort` and `LiveRuntimeInventory`) installs the pinned
  Mailpit through the same flow; Mailpit needs no preparation tools. A Mailpit folder that an
  earlier copy embedded (`mail-runtimes/`) is reused, and nothing is downloaded. It registers the
  runtime with `MailManager.registerRuntime`, which chooses the ports, never replaces a saved
  runtime, and never touches the inbox. Only Install Mailpit…, Start, and Runtimes › Install…
  call it. `OnDemandInstallFlow.offer(of:log:)` builds the `ServiceRuntimeOffer` of both.
- A RustFS or Mailpit build from Check for Runtime Updates goes to `StorageRuntimeAdoption` or
  `MailRuntimeAdoption`: without a saved runtime it is registered, else it goes through the
  journaled runtime update.
- The Tunnels model calls `connectStartupTunnels()` after a successful `load()`. `stopAll()`
  throws while a connector still runs, so Quit is cancelled.
- At launch, before the features load: abandoned staging folders are removed, and an outdated
  command-line launcher is refreshed once, off the main actor
  (`LiveConfiguration.refreshesCommandLineLauncher`). A run with another data root never
  touches the user's launcher. It keeps Jerd's preferences in its own defaults domain
  (`LiveConfiguration.defaultsSuiteName`), never in the user's `dev.jerd.app`. AppKit and SwiftUI still
  write the window frame, the sidebar width, and the menu bar item state to `dev.jerd.app`, so
  such a run copies that domain at launch and writes it back at quit (`PreferenceGuard`).

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdLiveTests
```

Every adapter depends on a small role protocol (`HelperControlling`, `SiteChangeApplying`,
`DatabaseManaging`, `TunnelControlling`, …) that the domain type conforms to here. The tests
use recording fakes: no helper, no network, no process, and only temporary folders.
