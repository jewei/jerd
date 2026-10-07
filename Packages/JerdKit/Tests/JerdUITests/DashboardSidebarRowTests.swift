import AppKit
import SwiftUI
import Testing

@testable import JerdUI

@Suite("Dashboard sidebar rows")
@MainActor
struct DashboardSidebarRowTests {
    private func height(of page: DashboardPage, isSelected: Bool) -> CGFloat {
        let host = NSHostingView(rootView: DashboardSidebarRow(page: page, isSelected: isSelected))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("Every page row has the same height, selected or not, whatever the size of its symbol")
    func everyRowHasOneHeight() {
        _ = NSApplication.shared
        let heights = DashboardPage.allCases.flatMap { page in
            [height(of: page, isSelected: false), height(of: page, isSelected: true)]
        }
        #expect(Set(heights) == [DashboardSidebarRow.rowHeight], "Row heights: \(heights)")
    }
}
