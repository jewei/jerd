/// The window frame around a snapshot.
package enum SnapshotChrome: Hashable, Sendable {
    /// Only the view, on the window background. The canvas size is the content size.
    case content

    /// A titled window with a unified toolbar. The canvas size is the full window frame,
    /// and SwiftUI toolbar items and the title come from the view.
    case window(title: String)
}
