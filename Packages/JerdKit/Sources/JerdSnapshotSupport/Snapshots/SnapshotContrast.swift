/// The Increase Contrast setting of one snapshot process. AppKit reads it once, when the
/// application starts, so one process renders only one contrast setting.
package enum SnapshotContrast: String, CaseIterable, Sendable {
    case standard
    case increased
}
