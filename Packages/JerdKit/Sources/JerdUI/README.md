# JerdUI

JerdUI contains the main window, the menu bar menu, the app commands, the feature view
models, and the port protocols that the UI needs. It does no file, process, or network
work: every effect goes through a port. JerdLive implements the ports; JerdUIFixtures
implements them in memory.

## Structure

| Folder | Contents |
| --- | --- |
| `App/` | `AppState` (the root model), `AppDependencies` (all ports), `AppInfo`, the staged quit (`ShutdownCoordinator`, `ShutdownPhase`, `ShutdownParticipant`), `AppAlert`. |
| `Shell/` | `JerdWorkspace` (window content and toolbar), `WorkspaceColumns` with the sidebar and detail column views, `WorkspaceStackSplit` (the SwiftUI split of snapshots and tests), `NavigationState`, `AppCommands`, `MenuBarContent`, the section picker, the sidebar toggle, retained pages, placeholders. |
| `Shared/` | `OperationState`, `OperationLock`, `ServicePoller`, `PollingPolicy`, `PollingTask`, `Clipboard`, the effect ports, `WorkspaceFeature` with its value types, and the `isQuitting` environment value. |
| `Features/Dashboard/` | The overview cards with their button rule (`CardActionRule`) and the runtimes row. |
| `Features/Settings/` | Appearance, Runtimes, Advanced (with Command-Line Tools and the shared `RegistrationStore`), and About, each with its model and ports. |
| `Features/Databases/` | `DatabasesPort`, `DatabasesModel`, the sidebar, the service page, the engine list (`DatabaseEnginesSection`), and the editor, retained, and restore sheets. |
| `Features/Storage/` | `StoragePort`, `StorageModel`, the bucket sidebar, the storage and bucket pages, Add Bucket, and the ports sheet. |
| `Features/Mail/` | `MailPort`, `MailModel`, the Mail page, and the ports sheet. |
| `Features/DataServices/` | What the three service features share: `ServicePorts`, state display (with `stuck`), files, port rules, the ports sheet, the missing-runtime banner with the reason of a failed bundled setup (`MissingRuntimeBanner`), and the state banner (`ServiceStateBanner`). A failed service shows one cause line, Open Log, and the last three log lines with short paths behind a disclosure (`ServiceFailureSummary`), not the whole log tail of the reason. |
| `Features/Sites/` | `SitesModel` (`SitesPort`): the sidebar, site page, site editor, HTTPS approval, system setup states. |
| `Features/Tunnels/` | `TunnelsModel` (`TunnelsPort`): the tunnel page, tunnel editor, and connector log, inside Sites. |

## Rules

1. Write each feature as a model, a port, pages, and a fixture. A view never calls a port.
2. A model is `@MainActor @Observable final class <Feature>Model`. It has one
   `OperationState`, `refresh()` for the poller, and, for a service, `shutdown() async -> Bool`
   and `resumeAfterCancelledQuit()` through `ShutdownParticipant`.
3. Show an error once, on the page that owns the failed operation: `OperationFailureBanner`
   at the top of the page, or an `InlineMessage` row in the section of the action. Only a
   cancelled quit and a failed system setup use the window alert (`AppState.alert`).
4. Every step that removes or changes data or the system asks first, with its own title,
   message, and confirm button. Destructive confirms never use Return.
5. Buttons and menu items use Title Case. Descriptions use sentence case.
6. Every page stays alive behind the visible one (`retainedPage(isVisible:)`). A hidden page
   takes no clicks, no keyboard focus, and no VoiceOver attention, and it announces nothing.
   But its open sheets, dialogs, and alerts stay usable. Never put `.disabled` on a view that
   presents a sheet, a dialog, or an alert: the presentation inherits it. Disable each button.
7. Copy through `AppState.clipboard`, so the toast shows from any page, sidebar, or menu.
8. Some work changes the system or the shared configuration: sites, HTTPS setup, recovery,
   PHP registrations, the default PHP, runtime activation, and command-line tools. This work
   runs under `AppState.operationLock`. Only one such operation runs at a time, and the quit
   waits for it.
9. Read and change PHP registrations and the default PHP only through
   `AppState.registrations` (`RegistrationStore`), so every page shows the same values.

## Database engines on demand

The app includes Redis, but not MySQL and PostgreSQL; `DatabasesPort.runtimeOffers()` lists the
pinned engines that Jerd can install, with the engine version (`PostgreSQL 18.6`, not the
Postgres.app release), download size, and source host. Redis never shows an install action. Nothing is
downloaded without a user action.

- The Databases page without a selected service lists every engine (`DatabaseEnginesSection`):
  installed with its versions, or "Install MySQL…" with the download size. Its Add buttons are
  only for installed engines, so the default button never starts a download and no engine has
  two entry points there. Install asks first (title, size, source, checks, and the free disk
  space), then shows the step, a progress bar, and Cancel in the row.
  A service page shows a running installation as a banner with Cancel. A failure or a cancel
  shows once, as a dismissible banner, with the reason (offline, checksum, disk space).
- Add Database lists every engine. For an engine without a runtime it shows the pinned version
  and a note, and its confirm button is "Install and Create": one flow installs the engine, then
  creates and starts the service. The progress shows in the sheet; Cancel stops the download and
  creates nothing; a failure stays in the sheet.
- The Dashboard card and the empty page offer Add Database at first launch. They say "Install it
  in Runtimes" only when the app has no pins at all.
- Add Database for an engine that gets a runtime while the sheet is open (from the page,
  Runtimes, or another sheet) takes that runtime and can save.
- Runtimes shows a pinned engine without an installed version as "Available" with Install…,
  which asks first with the same words (`RuntimeInstallCopy`).
- One installation runs at a time. The two pages share one installer, so each page turns off
  its Install while the other one installs (`runtimeInstallElsewhere`). Quit cancels a running
  installation before its final rename.

## Dashboard cards

Every card follows one button rule (`CardActionRule`, tested per card and state in
`FeatureCardTests`):

| Feature state | Actions, leading to trailing | Primary (the next step) |
| --- | --- | --- |
| Nothing registered | Add Site… / Add Database… | Add |
| Stopped | Start (Sites, Databases: Start All) | Start |
| Running | Stop (Stop All), then the Open step: Open Site, Open Console, Open Inbox | Open |
| Running, no Open step (Databases) | Stop All | none |

- At most two actions: the lifecycle action, then the Open step. Stop is never primary.
- A stopped feature has no Open step. The Open step of Sites opens the first served site in
  sidebar order; its help and spoken title name the site. The menu bar lists every site.
- Lifecycle titles on a card are short verbs, because the card title names the subject. The
  spoken title keeps the subject (`FeatureAction.spokenTitle`, for example "Stop Storage").
- So both actions stand in one row on every card at the minimum window size, and cards in one
  row keep one height. Only a larger text size puts them in a column. No card hides an action
  in a menu.
- The card's own Open › link shows the feature's page.

## Sheets and Quit

AppKit does not start a quit while a window shows a sheet, so every quit path first ends every
open sheet (in JerdLive):

| Path | Hook |
| --- | --- |
| ⌘Q and the app menu, the menu bar item | `ApplicationQuit.request()` |
| The Dock menu Quit, logout, restart, shutdown (the quit Apple Event) | `LiveApp.installQuitEventHandler()` in `applicationWillFinishLaunching` (`QuitAppleEventHandler`); it calls `ApplicationQuit.request()` |
| Sparkle "Install and Relaunch" | `updaterWillRelaunchApplication` calls `ApplicationQuit.endOpenSheets()`; Sparkle then terminates |
The decision, checked against the macOS Human Interface Guidelines:

- Jerd's sheets are short dialogs: a name, a port, a folder, a token. They are not documents.
  Every saved value is already on disk; a sheet holds only input that the user has not
  confirmed yet.
- Cancel and Escape end a sheet without a question. The HIG keeps confirmations for actions
  that destroy data that the user cannot get back. A Quit that asks while Cancel does not
  would give one sheet two rules.
- So Quit ends a sheet exactly as its Cancel does, and does not ask. The draft goes, a typed
  tunnel token is cleared from memory, and a waiting HTTPS approval is discarded. Work that the
  sheet already started is not cut: the staged quit waits for it.
- Every presenter builds its binding with `SheetBinding`. When SwiftUI or AppKit ends a sheet,
  the binding runs the sheet's own dismissal (`dismissSheet()`, `cancelEditor()`,
  `cancelPorts()`, …) and never only clears the value. `SheetDismissalTests` proves the binding
  and each dismissal. That AppKit's `endSheet` clears the binding is SwiftUI behavior; the live
  run checks it.
- If a sheet ever holds input that is hard to type again, it asks once, with the same alert.
  It asks from its Cancel and from Quit, never from only one of them.

## Add a feature

Each feature package touches the shell in a few marked lines only. Every other line of the
shell stays as it is.

1. **Model and port.** Add the port to `AppDependencies` (or to `ServicePorts`) and build the
   model in `AppState.init`; add it to `features`. Give the model the shared lock and the
   navigation it needs as init arguments, never the whole `AppState`.
2. **`WorkspaceFeature`.** Conform the model: the dashboard card (`summary`), the menu bar
   entries (`menuItems`), the banner activity, `pollingPolicy`, and its shutdown
   participants. Two members have defaults. `pollingTasks` gives one loop at `pollingPolicy`.
   Return two `PollingTask`s for two kinds of state, for example sites at `.environment` and
   tunnels at `.tunnels`. `newItemAction` is nil. Return the File › New command, for
   example "New Site…". ⌘N runs it also when the sidebar is hidden.
3. **Page.** Replace the section's line in `WorkspaceDetail.page(for:)`.
4. **Sidebar.** Replace the section's line in `WorkspaceSidebar.content`. Bind the `List`
   to `state.sidebarSelection(in:)` and tag each row with its `SidebarSelection`. Put the
   footer below the list with `.sidebarFooter { SidebarFooter(…) }`.
5. **Toolbar.** Replace the section's `EmptyView()` in `SectionToolbar`. Only the current
   section shows its items. Use icon buttons with a `Label`, a `.help` text, and an
   accessibility identifier.
6. **Sheets.** Keep the sheet state in the model (`var sheet: <Feature>Sheet?`), so the
   page, the sidebar, the toolbar, and ⌘N all open the same sheet. Present it with
   `.sheet(item: SheetBinding.item(…))` on the page root. Navigation never closes it.
7. **Quit.** The quit stops a feature only after its `launch()` finished. While a quit runs,
   the shell turns off every card and menu bar action of the feature. Pages, sidebars, and
   toolbars read `@Environment(\.isQuitting)` and turn off each control that starts work;
   Cancel and Close in a sheet stay on. A model also refuses new work after its own
   `shutdown()` started (`isShuttingDown`).

```swift
// 1–2. The model.
@MainActor @Observable
public final class MailModel: WorkspaceFeature, ShutdownParticipant {
    public private(set) var operation: OperationState = .idle
    public internal(set) var isShuttingDown = false
    public var sheet: MailSheet?
    @ObservationIgnored private let port: any MailPort
    public init(port: any MailPort) { self.port = port }

    public let section = AppSection.mail
    public let shutdownPhase = ShutdownPhase.mail
    public var pollingPolicy: PollingPolicy { .services }
    public var shutdownParticipants: [any ShutdownParticipant] { [self] }
    public var summary: FeatureSummary { FeatureSummary(status: DisplayStatus("Ready", tone: .ready), summary: "…") }
    public var menuItems: [MenuBarItem] { [] }
    public var bannerActivity: BannerActivity? { nil }
    public var newItemAction: FeatureAction? {
        FeatureAction(id: "mail.new", title: "Send Test Email…", isEnabled: !isShuttingDown) { [weak self] in
            self?.sheet = .testEmail
        }
    }
    public func launch() async { await refresh() }
    public func refresh() async { /* read the snapshot */ }
    public func shutdown() async -> Bool { isShuttingDown = true; /* stop; false keeps Jerd open */ return true }
    public func resumeAfterCancelledQuit() { isShuttingDown = false }
}

// 3, 6, 7. The page presents the model's sheet and turns off work during a quit.
struct MailPage: View {
    @Bindable var model: MailModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        FormPage {
            PageHeader("Mail", subtitle: "A local inbox for your application's test emails.")
        } messages: {
            OperationFailureBanner(operation: model.operation, identifier: "mail.error") { /* dismiss */ }
        } content: {
            Button("Send Test Email…") { model.sheet = .testEmail }
                .disabled(isQuitting || model.isShuttingDown)
        }
        .sheet(item: SheetBinding.item({ model.sheet }, dismiss: model.dismissSheet)) { sheet in
            MailSheetView(model: model, sheet: sheet)
        }
    }
}

// 4. The sidebar (Mail has none; this is the pattern of the other sections).
struct BucketsSidebar: View {
    let state: AppState
    let model: StorageModel
    var body: some View {
        List(selection: state.sidebarSelection(in: .storage)) {
            ForEach(model.buckets) { bucket in
                SidebarRow(bucket.name, status: bucket.status).tag(SidebarSelection.bucket(bucket.name))
            }
        }
        .listStyle(.sidebar)
        .sidebarFooter { SidebarFooter(addTitle: "Add Bucket…") { model.sheet = .addBucket } }
    }
}

// 5. In SectionToolbar: `case .storage: StorageToolbar(model: state.storage)`.
```

8. In JerdUIFixtures, add an in-memory port (an actor that records calls), sample data
   with fixed dates, and scenarios. Each scenario becomes one snapshot entry:

```swift
case mailRunning = "mail-running"   // in the scenario enum, with its navigation and prepare step
```

## Window split

`JerdWorkspace(state:split:)` owns the toolbar. The toolbar belongs to the window, so the
section picker stays centered in the window and the sidebar button stays at the leading edge
in every section, also with a hidden sidebar. The split comes from the caller:

- The app passes JerdLive's `WorkspaceSplit`: a native AppKit split view with the system
  sidebar background from the top edge to the bottom edge, an animated collapse, a saved
  width, and an accessible splitter.
- Snapshots and tests use `JerdWorkspace(state:)`, which shows `WorkspaceStackSplit`, a
  SwiftUI approximation with the same structure. Its sidebar has the ideal width with the
  app's limit (`SidebarWidthLimit`), so at 820 pt it is 182 pt wide and stays left of the
  picker. It does not resize, animate, or save the width, its sidebar background is only
  similar to the system one, and offscreen it draws the trailing toolbar items next to the
  picker, not at the trailing edge. Check those details in the running app.

## Snapshots

```sh
./dev snapshots                 # every page and the component gallery
./dev snapshots dashboard about # some pages
```

The images are in `.build/snapshots`, named `<scenario>-<light|dark>-<standard|compact|full>.png`.
Look at every image after a change. `PageSnapshotTests` renders every scenario once with
`jerd-snapshots --check`, in its own process, so the rendering never holds the main actor of
the test run. The compact
images are the minimum window (820 × 540, toolbar included): nothing may be cut off there.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdUITests
```
