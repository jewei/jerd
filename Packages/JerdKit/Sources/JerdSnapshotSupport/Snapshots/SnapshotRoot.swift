import SwiftUI

/// Fixes the environment values that can change output between runs: locale, time zone,
/// calendar, color scheme, and animations. Increase Contrast comes from the process setting
/// (see `SnapshotProcessSettings`), so SwiftUI and AppKit controls always agree.
struct SnapshotRoot<Content: View>: View {
    let content: Content
    let appearance: SnapshotAppearance

    var body: some View {
        content
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, .gmt)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.colorScheme, appearance.colorScheme)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }
}
