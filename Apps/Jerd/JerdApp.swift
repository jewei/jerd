import JerdLive
import JerdUI
import SwiftUI

/// The scenes of Jerd: the one main window and the menu bar item. There is no Settings scene:
/// Settings… (⌘,) opens Dashboard › Appearance in the main window.
@main
struct JerdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let live = delegate.live
        Window("Jerd", id: MainWindowPresenter.windowID) {
            JerdWorkspace(state: live.state) { columns in
                WorkspaceSplit(columns: columns)
            }
            .connectsMainWindow(to: live.windows)
        }
        .defaultSize(width: 980, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(state: live.state)
            CommandGroup(replacing: .appTermination) {
                Button("Quit Jerd") { ApplicationQuit.request() }
                    .keyboardShortcut("q")
            }
        }

        MenuBarExtra(isInserted: menuBarBinding(live.state.appearance)) {
            MenuBarContent(state: live.state) { ApplicationQuit.request() }
        } label: {
            MenuBarLabel(appearance: live.state.appearance, images: live.iconImages)
                .connectsMainWindow(to: live.windows)
        }
    }

    /// The menu bar item follows the Appearance switch.
    private func menuBarBinding(_ appearance: AppearanceModel) -> Binding<Bool> {
        Binding {
            appearance.showMenuBar
        } set: {
            appearance.showMenuBar = $0
        }
    }
}
