import JerdDesign
import SwiftUI

/// The content of the main window: the sidebar toggle, the section picker, the section's
/// toolbar items, the sidebar and detail split, and the window alert.
///
/// The toolbar belongs to the window, not to a split column, so the picker stays centered in the
/// window and the sidebar button stays at the leading edge in every section, also when a sidebar
/// is hidden. The split itself comes from `split`: the app passes the native AppKit
/// split view of JerdLive (`WorkspaceSplit`); snapshots and tests use `WorkspaceStackSplit`.
public struct JerdWorkspace<Split: View>: View {
    @Bindable var state: AppState
    private let split: (WorkspaceColumns) -> Split

    /// - Parameter split: Shows the two columns. It gets new `WorkspaceColumns` each time the
    ///   section or the sidebar visibility changes.
    public init(state: AppState, @ViewBuilder split: @escaping (WorkspaceColumns) -> Split) {
        self.state = state
        self.split = split
    }

    public var body: some View {
        split(WorkspaceColumns(state: state))
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
            .frame(
                minWidth: WindowMetrics.minimumContentSize.width, minHeight: WindowMetrics.minimumContentSize.height
            )
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

    private var isAlertPresented: Binding<Bool> {
        Binding {
            state.alert != nil
        } set: { isPresented in
            if !isPresented { state.alert = nil }
        }
    }
}

extension JerdWorkspace where Split == WorkspaceStackSplit {
    /// The workspace with the SwiftUI approximation of the split, for snapshots and tests.
    public init(state: AppState) {
        self.init(state: state) { columns in WorkspaceStackSplit(columns: columns) }
    }
}
