import JerdDesign
import SwiftUI

/// A SwiftUI approximation of the app's native split (JerdLive `WorkspaceSplit`), for snapshots
/// and tests, which have no app to host an AppKit split view controller. It has the same
/// structure: a full-height sidebar of the ideal width with a hairline, then the detail column.
/// It does not resize, animate, or save the width; the native split does.
public struct WorkspaceStackSplit: View {
    let columns: WorkspaceColumns

    public var body: some View {
        HStack(spacing: 0) {
            if columns.isSidebarVisible {
                columns.sidebar
                    .frame(width: WindowMetrics.sidebarIdealWidth)
                    // A background ignores the safe area, so it reaches under the toolbar.
                    .background(.background.secondary)
                Divider()
                    .ignoresSafeArea(.container, edges: .top)
            }
            columns.detail
        }
    }
}
