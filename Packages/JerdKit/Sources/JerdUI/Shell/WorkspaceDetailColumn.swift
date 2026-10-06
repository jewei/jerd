import JerdDesign
import SwiftUI

/// The detail column of the main window: the retained pages, the operation banner, and the copy
/// toast. Like `WorkspaceSidebarColumn`, it sets the window values that it needs itself.
public struct WorkspaceDetailColumn: View {
    let state: AppState

    public var body: some View {
        WorkspaceDetail(state: state)
            .detailColumn(copyFeedback: copyFeedback, operation: operationBanner)
            .environment(\.isQuitting, state.isQuitting)
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
}
