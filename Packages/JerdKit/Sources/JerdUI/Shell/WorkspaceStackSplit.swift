import JerdDesign
import SwiftUI

/// A SwiftUI approximation of the app's native split (JerdLive `WorkspaceSplit`), for snapshots
/// and tests, which have no app to host an AppKit split view controller. It has the same
/// structure: a full-height sidebar with a hairline, then the detail column. The sidebar has the
/// width of a new window's sidebar with the app's limit (`SidebarWidthLimit`), so in a narrow
/// window it stays left of the section picker as in the app.
/// It does not resize, animate, or save the width; the native split does.
public struct WorkspaceStackSplit: View {
    let columns: WorkspaceColumns

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if columns.isSidebarVisible {
                    columns.sidebar
                        .frame(width: Self.sidebarWidth(windowWidth: proxy.size.width))
                        // A background ignores the safe area, so it reaches under the toolbar.
                        .background(.background.secondary)
                    Divider()
                        .ignoresSafeArea(.container, edges: .top)
                }
                columns.detail
            }
        }
    }

    /// The sidebar width in a window of `windowWidth`: the ideal width, limited like the app's.
    static func sidebarWidth(windowWidth: CGFloat) -> CGFloat {
        SidebarWidthLimit.idealWidth(windowWidth: windowWidth)
    }
}
