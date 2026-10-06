import SwiftUI

extension View {
    /// Keeps a page alive while another section shows, so its scroll position, its editors,
    /// and its sheets survive navigation. A hidden page takes no clicks, no keyboard focus, and
    /// no VoiceOver attention, and it announces nothing. See `RetainedPageModifier`.
    func retainedPage(isVisible: Bool) -> some View {
        modifier(RetainedPageModifier(isVisible: isVisible))
    }
}
