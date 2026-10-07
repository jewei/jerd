import SwiftUI

/// The menu commands of Jerd: About and Check for Updates… in the app menu, File › New (⌘N)
/// for the current section, Settings… (⌘,),
/// Show or Hide Sidebar (⌃⌘S), and the five sections (⌘1…⌘5) in the View menu.
public struct AppCommands: Commands {
    let state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            CommandButton(command: .about, state: state)
            CommandButton(command: .checkForUpdates, state: state)
        }
        CommandGroup(replacing: .newItem) {
            CommandButton(command: .newItem, state: state)
        }
        CommandGroup(replacing: .appSettings) {
            CommandButton(command: .settings, state: state)
        }
        CommandGroup(replacing: .sidebar) {
            CommandButton(command: .toggleSidebar, state: state)
            Divider()
            ForEach(AppSection.allCases) { section in
                CommandButton(command: .showSection(section), state: state)
            }
            Divider()
        }
    }
}
