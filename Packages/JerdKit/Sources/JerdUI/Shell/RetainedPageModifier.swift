import JerdDesign
import SwiftUI

/// Hides a retained page without removing it, and without `.disabled`.
///
/// A sheet, dialog, or alert inherits the environment of the view that presents it, so a
/// disabled hidden page would leave its open sheet with disabled buttons and hide it from
/// VoiceOver. Instead, `.focusable(false)` removes the hidden page from the key view loop, and
/// `accessibilityHidden` removes it from VoiceOver; neither reaches the sheet's window.
/// `interactions: []` keeps the visible page itself from becoming a stop in the key view loop.
struct RetainedPageModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .focusable(isVisible, interactions: [])
            .accessibilityHidden(!isVisible)
            .transformEnvironment(\.messageAnnouncer) { announcer in
                if !isVisible { announcer = .silent }
            }
            .zIndex(isVisible ? 1 : 0)
    }
}
