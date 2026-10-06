import JerdDesign
import SwiftUI

/// The one row of an empty sidebar section: why it is empty (loading, not loaded, or nothing
/// added yet). It cannot be selected. Every section sidebar uses it, so no list is a bare header.
struct SidebarPlaceholder: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    /// The text for a section of a service feature, from its load state.
    nonisolated static func text(for loadState: ServiceLoadState, items: String, settings: String) -> String {
        switch loadState {
        case .loading: "Loading \(items)…"
        case .loaded: "No \(items) added"
        case .failed: "\(settings) settings could not be loaded"
        }
    }

    var body: some View {
        Text(text)
            .textRole(.detail)
            .padding(.vertical, Spacing.tight)
            .selectionDisabled()
    }
}
