import SwiftUI

/// Shows every design component in every state, one gallery page at a time. Snapshots and
/// previews use it; the app never shows it.
package struct ComponentGallery: View {
    private let page: GalleryPage

    package init(page: GalleryPage) {
        self.page = page
    }

    package var body: some View {
        switch page {
        case .status: GalleryStatusPage()
        case .headers: GalleryHeadersPage()
        case .rows: GalleryRowsPage()
        case .banners: GalleryBannersPage()
        case .cards: GalleryCardsPage()
        case .sheet: GallerySheetPage()
        case .destructiveSheet: GalleryDestructiveSheetPage()
        case .workspace: GalleryWorkspace(showsEmptyState: false)
        case .empty: GalleryWorkspace(showsEmptyState: true)
        }
    }
}
