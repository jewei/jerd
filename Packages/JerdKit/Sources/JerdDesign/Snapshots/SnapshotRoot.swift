import SwiftUI

/// Fixes every environment value that can change output between runs: locale, time zone,
/// calendar, color scheme, and animations.
struct SnapshotRoot<Content: View>: View {
    let content: Content
    let appearance: SnapshotAppearance

    var body: some View {
        content
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, .gmt)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.colorScheme, appearance.colorScheme)
            // The window appearance alone does not reach SwiftUI offscreen.
            .environment(\._colorSchemeContrast, appearance.isIncreasedContrast ? .increased : .standard)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }
}
