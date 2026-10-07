import SwiftUI

extension View {
    /// Removes the window title from the toolbar on macOS 15 and later, so a centered section
    /// picker keeps its place at the minimum window width. macOS 14 has no API for this.
    @ViewBuilder
    public func removingToolbarTitle() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}
