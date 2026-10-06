import CoreGraphics
import JerdDesign

/// The sidebar widths that a window allows. The section picker is centered in the window, so a
/// wide sidebar in a narrow window would reach under the picker. The picker must
/// not cross the sidebar edge. The macOS 26 picker is 440 pt wide, so at the minimum window
/// width (820 pt) only 182 pt stay left of it: there the sidebar may be narrower than its usual
/// minimum of `WindowMetrics.sidebarMinimumWidth`, but never narrower than `narrowestWidth`.
package enum SidebarWidthLimit {
    /// The space between the sidebar edge and the picker.
    package static let pickerGap: CGFloat = 8
    /// The sidebar is never narrower than this, also when it then reaches under the picker.
    package static let narrowestWidth: CGFloat = 160

    /// The allowed sidebar widths for a window and picker width.
    package static func widths(windowWidth: CGFloat, pickerWidth: CGFloat) -> ClosedRange<CGFloat> {
        let free = ((windowWidth - pickerWidth) / 2 - pickerGap).rounded(.down)
        let maximum = min(max(free, narrowestWidth), WindowMetrics.sidebarMaximumWidth)
        return min(WindowMetrics.sidebarMinimumWidth, maximum)...maximum
    }
}
