import SwiftUI

/// The system setup commands: Login Items & Extensions, Reconnect Helper…, and Remove System
/// Setup…. A separate view, so the shell can move it into the toolbar.
struct SystemSetupMenu: View {
    let model: SitesModel

    var body: some View {
        Menu {
            Button("Open Login Items & Extensions") { model.openLoginItems() }
            Button("Reconnect Helper…") { model.confirmation = .reconnectHelper }
            Divider()
            Button("Remove System Setup…", role: .destructive) { model.confirmation = .removeSystemSetup }
        } label: {
            Label("System Setup", systemImage: "lock.shield")
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(!model.canChange)
        .help("System setup")
        .accessibilityIdentifier("sites.system-setup-menu")
    }
}
