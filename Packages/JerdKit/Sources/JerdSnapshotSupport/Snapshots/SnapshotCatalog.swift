import SwiftUI

/// The list of views that `jerd-snapshots` renders. Register a page with one line:
///
///     catalog.add("sites-running") { WorkspaceView(model: .running) }
package struct SnapshotCatalog {
    package private(set) var entries: [SnapshotEntry] = []

    package init() {}

    /// Adds a view. Names must be unique; the command refuses to run with `duplicateNames`.
    /// - Parameters:
    ///   - sizes: Defaults to both window sizes, standard and compact.
    ///   - appearances: Defaults to light and dark. Add the contrast variants where useful.
    ///   - chrome: Defaults to a titled window with the toolbar.
    ///   - isReady: For content that loads in `.task`: the renderer waits until it is true.
    package mutating func add(
        _ name: String, sizes: [SnapshotSize] = SnapshotSize.windowSizes,
        appearances: [SnapshotAppearance] = SnapshotAppearance.standard,
        chrome: SnapshotChrome = .window(title: "Jerd"), isReady: @escaping @MainActor () -> Bool = { true },
        @ViewBuilder view: @escaping @MainActor () -> some View
    ) {
        let entry = SnapshotEntry(
            name: name, sizes: sizes, appearances: appearances, chrome: chrome, isReady: isReady
        ) {
            AnyView(view())
        }
        entries.append(entry)
    }

    /// Names that more than one entry uses. Two entries with one name would overwrite files.
    package var duplicateNames: [String] {
        let counts = Dictionary(entries.map { ($0.name, 1) }, uniquingKeysWith: +)
        return entries.map(\.name).filter { counts[$0, default: 0] > 1 }.reduce(into: []) { names, name in
            if !names.contains(name) { names.append(name) }
        }
    }

    /// Every file name that a full run writes. Other PNG files in the output folder are stale.
    package var fileNames: Set<String> {
        Set(entries.flatMap(\.fileNames))
    }

    /// The entries that match any filter, in catalog order. No filters select every entry.
    package func entries(matching filters: [String]) -> [SnapshotEntry] {
        guard !filters.isEmpty else { return entries }
        return entries.filter { entry in filters.contains { entry.matches(filter: $0) } }
    }

    /// Filters that match no entry, so the command can report a mistyped name.
    package func unmatchedFilters(_ filters: [String]) -> [String] {
        filters.filter { filter in !entries.contains { $0.matches(filter: filter) } }
    }
}
