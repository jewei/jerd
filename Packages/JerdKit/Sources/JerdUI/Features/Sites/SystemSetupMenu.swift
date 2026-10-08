import SwiftUI

/// The system setup commands in the Sites toolbar: Login Items & Extensions, Reconnect
/// Helper…, and Remove System Setup…. Both changes ask first, on the Sites page.
struct SystemSetupMenu: View {
    let model: SitesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Menu {
            Button("Open Login Items & Extensions") { model.openLoginItems() }
            Button("Reconnect Helper…") { model.confirmation = .reconnectHelper }
                .disabled(!canChange)
            Divider()
            Button("Remove System Setup…", role: .destructive) { model.confirmation = .removeSystemSetup }
                .disabled(!canChange)
        } label: {
            Label("System Setup", systemImage: "lock.shield")
        }
        .help("System Setup: Login Items, Reconnect Helper, and Remove System Setup")
        .accessibilityIdentifier("sites.system-setup-menu")
    }

    private var canChange: Bool { model.canChangeSystem && !isQuitting }
}
