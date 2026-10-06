import JerdDesign
import SwiftUI

/// The content of the main window: the sidebar toggle, the section picker, the section's
/// toolbar items, one sidebar and detail split (window-level toolbar, so its items never move), the retained pages, the operation banner, the
/// copy toast, and the window alert.
public struct JerdWorkspace: View {
    /// The height of the unified toolbar above the content. The window minimum is a window
    /// size, so the content may use only what the toolbar leaves.
    static let toolbarHeight: CGFloat = 52

    /// The smallest content: the minimum window less the toolbar. The app scene uses
    /// `.windowResizability(.contentMinSize)`, so the window never gets smaller than
    /// `WindowMetrics.minimumSize` and never clips the bottom of a page or a sidebar footer.
    static let minimumContentSize = CGSize(
        width: WindowMetrics.minimumSize.width, height: WindowMetrics.minimumSize.height - toolbarHeight)

    @Bindable var state: AppState
    /// The sidebar width, shared by every section.
    @State private var sidebarWidth = WindowMetrics.sidebarIdealWidth

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        // A plain split, not `NavigationSplitView`: the split view lays out the toolbar per
        // column, so hiding the sidebar moved the section picker and the sidebar button.
        HStack(spacing: 0) {
            if state.navigation.isSidebarVisible(in: state.navigation.section) {
                WorkspaceSidebar(state: state)
                    .frame(width: sidebarWidth)
                SidebarDivider(width: $sidebarWidth)
            }
            WorkspaceDetail(state: state)
                .detailColumn(copyFeedback: copyFeedback, operation: operationBanner)
        }
        .removingToolbarTitle()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SidebarToggle(state: state)
            }
            ToolbarItem(placement: .principal) {
                SectionPicker(state: state)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                SectionToolbar(state: state)
            }
        }
        .environment(\.isQuitting, state.isQuitting)
        .transaction(value: state.navigation.section) { transaction in
            transaction.animation = nil
        }
        .frame(minWidth: Self.minimumContentSize.width, minHeight: Self.minimumContentSize.height)
        .alert(
            state.alert?.title ?? "", isPresented: isAlertPresented, presenting: state.alert
        ) { _ in
            Button("OK") { state.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .onAppear { state.setWindowVisible(true) }
        .onDisappear { state.setWindowVisible(false) }
    }

    private var operationBanner: OperationBanner? {
        state.bannerActivity.map { activity in
            OperationBanner(
                activity.message, progress: activity.progress,
                stop: activity.stop.map { stop in
                    PageAction(
                        stop.title, role: .destructive, isEnabled: stop.isEnabled, identifier: stop.id,
                        perform: stop.perform)
                })
        }
    }

    private var copyFeedback: Binding<CopyFeedbackMessage?> {
        Binding {
            state.clipboard.feedback
        } set: { message in
            state.clipboard.feedback = message
        }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding {
            state.alert != nil
        } set: { isPresented in
            if !isPresented { state.alert = nil }
        }
    }
}
