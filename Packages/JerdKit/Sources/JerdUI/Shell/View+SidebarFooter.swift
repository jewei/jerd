import JerdDesign
import SwiftUI

extension View {
    /// Puts a footer at the bottom of a feature sidebar, below the list and above nothing else,
    /// for example `SidebarFooter` with the Add menu. Apply it to the sidebar `List`.
    public func sidebarFooter(@ViewBuilder _ footer: () -> some View) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0, content: footer)
    }
}
