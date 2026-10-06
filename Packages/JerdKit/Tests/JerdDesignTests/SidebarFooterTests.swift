import AppKit
import SwiftUI
import Testing

@testable import JerdDesign

/// Every sidebar footer has one height, so the footer line stays
/// in place when the user changes section.
@Suite("Sidebar footer")
@MainActor
struct SidebarFooterTests {
    private func height(of view: some View) -> CGFloat {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.frame(width: 220))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("The Add button form and the Add menu form have the same height, with or without a caption")
    func everyFormHasOneHeight() {
        let heights = [
            height(of: SidebarFooter(addTitle: "Add Bucket…") {}),
            height(of: SidebarFooter(addTitle: "Add Bucket…", caption: "3 buckets") {}),
            height(of: SidebarFooter(addTitle: "Add…") { Button("Add Site…") {} }),
            height(of: SidebarFooter(addTitle: "Add…", caption: "3 sites · 2 running") { Button("Add Site…") {} }),
        ]
        #expect(Set(heights).count == 1, "Heights: \(heights)")
        #expect(heights.first == SidebarFooter<EmptyView>.rowHeight + 1)
    }
}
