import SwiftUI

/// One named view in a `SnapshotCatalog`, rendered at each of its sizes in each appearance.
package struct SnapshotEntry: Identifiable {
    package let name: String
    package let sizes: [SnapshotSize]
    package let appearances: [SnapshotAppearance]
    package let chrome: SnapshotChrome
    package let makeView: @MainActor () -> AnyView

    package var id: String { name }

    package init(
        name: String, sizes: [SnapshotSize], appearances: [SnapshotAppearance] = SnapshotAppearance.standard,
        chrome: SnapshotChrome, makeView: @escaping @MainActor () -> AnyView
    ) {
        self.name = name
        self.sizes = sizes
        self.appearances = appearances
        self.chrome = chrome
        self.makeView = makeView
    }

    /// The file name of one rendering: `<name>-<appearance>-<size>.png`, for example
    /// `sites-light-standard.png`.
    package func fileName(appearance: SnapshotAppearance, size: SnapshotSize) -> String {
        "\(name)-\(appearance.rawValue)-\(size.name).png"
    }

    /// A filter matches an entry with the same name, or an entry whose name continues the
    /// filter after a hyphen. So `gallery` matches `gallery-status`, but not `gallerystatus`.
    package func matches(filter: String) -> Bool {
        name == filter || name.hasPrefix(filter + "-")
    }
}
