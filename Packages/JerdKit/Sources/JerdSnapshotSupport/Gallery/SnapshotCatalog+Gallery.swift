import JerdDesign

extension SnapshotCatalog {
    /// Registers every component gallery page.
    package mutating func addComponentGallery() {
        for page in GalleryPage.allCases {
            let chrome: SnapshotChrome = page.usesWindow ? .window(title: "Jerd") : .content
            add(page.snapshotName, sizes: page.sizes, appearances: page.appearances, chrome: chrome) {
                ComponentGallery(page: page)
            }
        }
    }
}
