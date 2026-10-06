import JerdDesign
import SwiftUI

/// The content of the main window: the section picker, one sidebar and detail split, the
/// retained pages, the operation banner, the copy toast, and the window alert.
public struct JerdWorkspace: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            WorkspaceSidebar(state: state)
        } detail: {
            WorkspaceDetail(state: state)
                .detailColumn(copyFeedback: copyFeedback, operation: operationBanner)
        }
        .removingToolbarTitle()
        .toolbar(removing: state.navigation.canToggleSidebar ? nil : .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SectionPicker(state: state)
            }
        }
        .transaction(value: state.navigation.section) { transaction in
            transaction.animation = nil
        }
        .frame(minWidth: WindowMetrics.minimumSize.width, minHeight: WindowMetrics.minimumSize.height)
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

    /// Each section keeps its own sidebar state. A collapse through the split view is saved
    /// for the current section only.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            state.navigation.isSidebarVisible(in: state.navigation.section) ? .all : .detailOnly
        } set: { visibility in
            state.navigation.setSidebarVisible(visibility != .detailOnly)
        }
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
