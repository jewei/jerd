import JerdDesign
import SwiftUI

/// One Dashboard page in the sidebar: its symbol and its title.
///
/// The symbols have different natural sizes. One symbol frame and one row height keep the rows
/// and the selection highlight the same height, as in the system sidebars.
struct DashboardSidebarRow: View {
    /// The square frame of each symbol, in points.
    static let symbolSide: CGFloat = 20
    /// The height of each row content, in points.
    static let rowHeight: CGFloat = 28

    let page: DashboardPage
    let isSelected: Bool

    var body: some View {
        Label {
            Text(page.title)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: page.systemImage)
                .symbolVariant(isSelected ? .fill : .none)
                .frame(width: Self.symbolSide, height: Self.symbolSide)
        }
        .frame(height: Self.rowHeight)
    }
}
