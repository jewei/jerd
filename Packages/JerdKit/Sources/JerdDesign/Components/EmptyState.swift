import SwiftUI

/// The system empty state (`ContentUnavailableView`) with Jerd's actions: one large primary
/// action and optional secondary actions.
public struct EmptyState<Actions: View>: View {
    private let title: String
    private let systemImage: String
    private let message: String
    private let actions: Actions

    public init(
        _ title: String, systemImage: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: Spacing.small) {
                actions
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
