import JerdDesign
import SwiftUI

/// The page of a section whose feature is not built yet. Only the workspace wiring uses it;
/// the feature work package replaces it with the feature's own page.
struct PlaceholderPage: View {
    static let message = "Built in the next work package."

    let section: AppSection

    var body: some View {
        EmptyState(section.title, systemImage: section.systemImage, message: Self.message)
    }
}
