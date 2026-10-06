# JerdUI

JerdUI contains the main window, the menu bar menu, the app commands, the feature view
models, and the port protocols that the UI needs. It does no file, process, or network
work: every effect goes through a port. JerdLive implements the ports; JerdUIFixtures
implements them in memory.

## Structure

| Folder | Contents |
| --- | --- |
| `App/` | `AppState` (the root model), `AppDependencies` (all ports), `AppInfo`, the staged quit (`ShutdownCoordinator`, `ShutdownPhase`, `ShutdownParticipant`), `AppAlert`. |
| `Shell/` | `JerdWorkspace` (window content), `NavigationState`, `AppCommands`, `MenuBarContent`, the section picker, retained pages, placeholders. |
| `Shared/` | `OperationState`, `ServicePoller`, `PollingPolicy`, `Clipboard`, the effect ports, and `WorkspaceFeature` with its value types. |
| `Features/Dashboard/` | The overview cards and the runtimes row. |
| `Features/Settings/` | Appearance, Runtimes, Advanced, and About, each with its model and ports. |

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
6. A hidden retained page uses `retainedPage(isVisible:)`; it announces nothing.
7. Copy through `AppState.clipboard`, so the toast shows from any page, sidebar, or menu.

## Add a feature

1. Add the port to `AppDependencies` and build the model in `AppState.init`; pass it in
   `features`. Replace the placeholder in `WorkspaceDetail` and `WorkspaceSidebar`.
2. Conform the model to `WorkspaceFeature`: the dashboard card, the menu bar entries, the
   banner activity, the polling policy, and its shutdown participants.

```swift
public protocol MailPort: Sendable {
    func snapshot() async throws -> MailSnapshot
    func start() async throws
}

@MainActor @Observable
public final class MailModel: WorkspaceFeature, ShutdownParticipant {
    public private(set) var operation: OperationState = .idle
    @ObservationIgnored private let port: any MailPort
    public init(port: any MailPort) { self.port = port }

    public let section = AppSection.mail
    public let shutdownPhase = ShutdownPhase.mail
    public var pollingPolicy: PollingPolicy { .services }
    public var shutdownParticipants: [any ShutdownParticipant] { [self] }
    public var summary: FeatureSummary { FeatureSummary(status: DisplayStatus("Ready", tone: .ready), summary: "…") }
    public var menuItems: [MenuBarItem] { [] }
    public var bannerActivity: BannerActivity? { nil }
    public func launch() async { await refresh() }
    public func refresh() async { /* read the snapshot */ }
    public func shutdown() async -> Bool { /* stop; false keeps Jerd open */ true }
    public func resumeAfterCancelledQuit() {}
}

struct MailPage: View {
    let model: MailModel
    var body: some View {
        FormPage {
            PageHeader("Mail", subtitle: "A local inbox for your application's test emails.")
        } messages: {
            OperationFailureBanner(operation: model.operation, identifier: "mail.error") { /* dismiss */ }
        } content: { /* sections */ }
    }
}
```

3. In JerdUIFixtures, add an in-memory port (an actor that records calls), sample data
   with fixed dates, and scenarios in `FixtureScenario`. Each scenario becomes one
   snapshot entry through `SnapshotCatalog.addJerdPages()`:

```swift
case mailRunning = "mail-running"   // in FixtureScenario, with its navigation and prepare step
```

## Snapshots

```sh
./dev snapshots                 # every page and the component gallery
./dev snapshots dashboard about # some pages
```

The images are in `.build/snapshots`, named `<scenario>-<light|dark>-<standard|compact|full>.png`.
Look at every image after a change. `PageSnapshotTests` renders every scenario.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdUITests
```
