import AppKit
import JerdDesign
import SwiftUI

/// The line between the sidebar and the detail column. Dragging it resizes the sidebar within
/// `WindowMetrics.sidebarMinimumWidth…sidebarMaximumWidth`. The workspace uses its own split,
/// not `NavigationSplitView`, because the split view moves the toolbar items with the sidebar
/// column (spec F 2.6: the section picker and the sidebar button never move).
struct SidebarDivider: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        if isInside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = dragStartWidth ?? width
                                dragStartWidth = start
                                width = Self.clampedWidth(start + drag.translation.width)
                            }
                            .onEnded { _ in dragStartWidth = nil })
            }
            .accessibilityHidden(true)
    }

    /// The sidebar width for a drag, kept between the minimum and the maximum.
    static func clampedWidth(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, WindowMetrics.sidebarMinimumWidth), WindowMetrics.sidebarMaximumWidth)
    }
}
