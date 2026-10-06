import CoreGraphics
import Testing

@testable import JerdDesign

@Suite("Sidebar width limit")
struct SidebarWidthLimitTests {
    @Test("The sidebar limit keeps a gap to the picker and narrows the sidebar only in a narrow window")
    func sidebarWidthLimit() {
        #expect(SidebarWidthLimit.widths(windowWidth: 980, pickerWidth: 360) == 200...280)
        #expect(SidebarWidthLimit.widths(windowWidth: 980, pickerWidth: 440) == 200...262)
        #expect(SidebarWidthLimit.widths(windowWidth: 820, pickerWidth: 440) == 182...182)
        #expect(SidebarWidthLimit.widths(windowWidth: 600, pickerWidth: 440) == 160...160)
    }

    @Test("A new sidebar has the ideal width where it fits, and the limit in a narrow window")
    func idealWidthFollowsTheLimit() {
        #expect(SidebarWidthLimit.idealWidth(windowWidth: 980) == WindowMetrics.sidebarIdealWidth)
        #expect(SidebarWidthLimit.idealWidth(windowWidth: 1600) == WindowMetrics.sidebarIdealWidth)
        #expect(SidebarWidthLimit.idealWidth(windowWidth: 820) == 182)
        #expect(SidebarWidthLimit.idealWidth(windowWidth: 600) == SidebarWidthLimit.narrowestWidth)
    }

    @Test("The ideal sidebar edge stays left of the centered picker at every supported window width")
    func idealSidebarStaysLeftOfThePicker() {
        for width in stride(from: WindowMetrics.minimumSize.width, through: 1600, by: 20) {
            let pickerStart = (width - SidebarWidthLimit.sectionPickerWidth) / 2
            #expect(SidebarWidthLimit.idealWidth(windowWidth: width) + SidebarWidthLimit.pickerGap <= pickerStart)
        }
    }
}
