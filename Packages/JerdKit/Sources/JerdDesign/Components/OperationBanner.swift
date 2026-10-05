import SwiftUI

/// The global progress bar at the bottom of the window: a spinner or progress value, the
/// operation message, and an optional Stop button. Place it with
/// `.safeAreaInset(edge: .bottom)` on the window content.
public struct OperationBanner: View {
    private let message: String
    private let progress: Double?
    private let stop: PageAction?

    /// - Parameter progress: A fraction from 0 to 1, or nil when the length is unknown.
    public init(_ message: String, progress: Double? = nil, stop: PageAction? = nil) {
        self.message = message
        self.progress = progress.map { min(max($0, 0), 1) }
        self.stop = stop
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.medium) {
                indicator
                Text(message)
                    .textRole(.detail)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .help(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let stop {
                    PageActionButton(action: stop, isPrimary: false)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.small + Spacing.hairline)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current operation")
    }

    @ViewBuilder private var indicator: some View {
        if let progress {
            ProgressView(value: progress)
                .frame(width: 96)
                .accessibilityLabel(message)
                .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(message)
        }
    }
}
