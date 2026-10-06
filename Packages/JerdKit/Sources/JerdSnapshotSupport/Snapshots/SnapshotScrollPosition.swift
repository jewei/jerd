/// Where the scroll views of a snapshot stand when the renderer captures it. The offscreen
/// window takes no scroll events, so the renderer sets the position itself before each pass.
package enum SnapshotScrollPosition: String, Hashable, Sendable {
    /// Every scroll view at its top: what the user sees first.
    case top
    /// Every scroll view that can scroll at its end, so the image shows the last sections and the
    /// end of a long sheet or page at the real window or sheet size.
    case end
}
