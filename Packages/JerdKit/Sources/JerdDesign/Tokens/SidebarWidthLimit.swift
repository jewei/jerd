import CoreGraphics

/// The sidebar widths that a window allows. The section picker is centered in the window, so a
/// wide sidebar in a narrow window would reach under the picker. The picker must
/// not cross the sidebar edge. The macOS 26 picker is 440 pt wide, so at the minimum window
/// width (820 pt) only 182 pt stay left of it: there the sidebar may be narrower than its usual
/// minimum of `WindowMetrics.sidebarMinimumWidth`, but never narrower than `narrowestWidth`.
///
/// The app's split measures the real picker; the SwiftUI split of the snapshots cannot, so it
/// uses `sectionPickerWidth`.
public enum SidebarWidthLimit {
    /// The space between the sidebar edge and the picker.
    public static let pickerGap: CGFloat = 8
    /// The sidebar is never narrower than this, also when it then reaches under the picker.
    public static let narrowestWidth: CGFloat = 160
    /// The width of the section picker on macOS 26 and later, for a layout that cannot measure it.
    public static let sectionPickerWidth: CGFloat = 440

    /// The allowed sidebar widths for a window and picker width.
    public static func widths(windowWidth: CGFloat, pickerWidth: CGFloat) -> ClosedRange<CGFloat> {
        let free = ((windowWidth - pickerWidth) / 2 - pickerGap).rounded(.down)
        let maximum = min(max(free, narrowestWidth), WindowMetrics.sidebarMaximumWidth)
        return min(WindowMetrics.sidebarMinimumWidth, maximum)...maximum
    }

    /// The width of a new sidebar: the ideal width, limited to the allowed widths.
    public static func idealWidth(windowWidth: CGFloat, pickerWidth: CGFloat = sectionPickerWidth) -> CGFloat {
        let allowed = widths(windowWidth: windowWidth, pickerWidth: pickerWidth)
        return min(max(WindowMetrics.sidebarIdealWidth, allowed.lowerBound), allowed.upperBound)
    }
}
