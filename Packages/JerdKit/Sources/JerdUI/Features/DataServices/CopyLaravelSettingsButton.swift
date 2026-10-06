import SwiftUI

/// The one "Copy Laravel Settings" button of the Databases, Storage, and Mail pages, so the
/// three pages show the same title and symbol.
struct CopyLaravelSettingsButton: View {
    let isEnabled: Bool
    let identifier: String
    let perform: @MainActor () -> Void

    var body: some View {
        Button("Copy Laravel Settings", systemImage: "doc.on.doc", action: perform)
            .disabled(!isEnabled)
            .accessibilityIdentifier(identifier)
    }
}
