# JerdUI

JerdUI contains the main window, the menu bar menu, the app commands, the feature view
models, and the port protocols that the UI needs. It does no file, process, or network
work: every effect goes through a port. JerdLive implements the ports; JerdUIFixtures
implements them in memory.

## Structure

| Folder | Contents |
| --- | --- |
| `App/` | `AppState` (the root model), `AppDependencies` (all ports), `AppInfo`, the staged quit (`ShutdownCoordinator`, `ShutdownPhase`, `ShutdownParticipant`), `AppAlert`. |
| `Shell/` | `JerdWorkspace` (window content), `NavigationState`, `AppCommands`, `MenuBarContent`, the section picker and toolbar, the sidebar toggle, retained pages, placeholders. |
| `Shared/` | `OperationState`, `OperationLock`, `ServicePoller`, `PollingPolicy`, `PollingTask`, `Clipboard`, the effect ports, `WorkspaceFeature` with its value types, and the `isQuitting` environment value. |
| `Features/Dashboard/` | The overview cards and the runtimes row. |
| `Features/Settings/` | Appearance, Runtimes, Advanced (with Command-Line Tools and the shared `RegistrationStore`), and About, each with its model and ports. |
| `Features/Databases/` | `DatabasesPort`, `DatabasesModel`, the sidebar, the service page, and the editor, retained, and restore sheets. |
| `Features/Storage/` | `StoragePort`, `StorageModel`, the bucket sidebar, the storage and bucket pages, Add Bucket, and the ports sheet. |
| `Features/Mail/` | `MailPort`, `MailModel`, the Mail page, and the ports sheet. |
| `Features/DataServices/` | What the three service features share: `ServicePorts`, state display (with `stuck`), files, port rules, the ports sheet, and the missing-runtime banner with the reason of a failed bundled setup (`MissingRuntimeBanner`). |
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
   takes no clicks, no keyboard focus, and no VoiceOver attention, and it announces nothing,
   but its open sheets, dialogs, and alerts stay usable. Never put `.disabled` on a view that
   presents a sheet, a dialog, or an alert: the presentation inherits it. Disable each button.
7. Copy through `AppState.clipboard`, so the toast shows from any page, sidebar, or menu.
8. Work that changes the system or the shared configuration (sites, HTTPS setup, recovery,
   PHP registrations, the default PHP, runtime activation, command-line tools) runs under
   `AppState.operationLock`: one such operation at a time, and the quit waits for it.
9. Read and change PHP registrations and the default PHP only through
   `AppState.registrations` (`RegistrationStore`), so every page shows the same values.

## Add a feature

Each feature package touches the shell in a few marked lines only. Every other line of the
shell stays as it is.

1. **Model and port.** Add the port to `AppDependencies` (or to `ServicePorts`) and build the
   model in `AppState.init`; add it to `features`. Give the model the shared lock and the
   navigation it needs as init arguments, never the whole `AppState`.
2. **`WorkspaceFeature`.** Conform the model: the dashboard card (`summary`), the menu bar
   entries (`menuItems`), the banner activity, `pollingPolicy`, and its shutdown
   participants. Two members have defaults: `pollingTasks` (one loop at `pollingPolicy`;
   return two `PollingTask`s for two kinds of state, for example sites at `.environment` and
   tunnels at `.tunnels`) and `newItemAction` (nil; return the File › New command, for
   example "New Site…", which ⌘N runs also when the sidebar is hidden).
3. **Page.** Replace the section's line in `WorkspaceDetail.page(for:)`.
4. **Sidebar.** Replace the section's line in `WorkspaceSidebar.content`. Bind the `List`
   to `state.sidebarSelection(in:)` and tag each row with its `SidebarSelection`. Put the
   footer below the list with `.sidebarFooter { SidebarFooter(…) }`.
5. **Toolbar.** Replace the section's `EmptyView()` in `SectionToolbar`. Only the current
   section shows its items. Use icon buttons with a `Label`, a `.help` text, and an
   accessibility identifier.
6. **Sheets.** Keep the sheet state in the model (`var sheet: <Feature>Sheet?`), so the
   page, the sidebar, the toolbar, and ⌘N all open the same sheet. Present it with
   `.sheet(item:)` on the page root. Navigation never closes it.
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
        .sheet(item: $model.sheet) { sheet in MailSheetView(model: model, sheet: sheet) }
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

## Snapshots

```sh
./dev snapshots                 # every page and the component gallery
./dev snapshots dashboard about # some pages
```

The images are in `.build/snapshots`, named `<scenario>-<light|dark>-<standard|compact|full>.png`.
Look at every image after a change. `PageSnapshotTests` renders every scenario. The compact
images are the minimum window (820 × 540, toolbar included): nothing may be cut off there.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdUITests
```
