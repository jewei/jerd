import SwiftUI

/// The fixed top of a page: the header, then page banners, then a divider. Header text starts
/// on the page text column; banners use the section column.
struct PageTop<Header: View, Messages: View>: View {
    let columns: PageColumns
    let header: Header
    let messages: Messages

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, columns.textInset)
                .padding(.vertical, Spacing.extraLarge)
            BannerStack {
                messages
            }
            .padding(.horizontal, columns.sectionInset)
            Divider()
        }
    }
}
