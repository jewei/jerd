import JerdDesign
import SwiftUI

extension View {
    /// Keeps a page alive while another section shows, so its scroll position, its editors,
    /// and its sheets survive navigation. A hidden page takes no clicks, no focus, and no
    /// VoiceOver attention, and it announces nothing.
    func retainedPage(isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .disabled(!isVisible)
            .accessibilityHidden(!isVisible)
            .transformEnvironment(\.messageAnnouncer) { announcer in
                if !isVisible { announcer = .silent }
            }
            .zIndex(isVisible ? 1 : 0)
    }
}
