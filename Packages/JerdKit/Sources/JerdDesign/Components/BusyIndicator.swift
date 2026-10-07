import SwiftUI

/// A small spinner for toolbars and headers. It always has a spoken label and a tooltip.
public struct BusyIndicator: View {
    private let label: String

    /// - Parameter label: What is in progress, for example "Checking for runtime updates".
    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        ProgressView()
            .controlSize(.small)
            .help(label)
            .accessibilityLabel(label)
    }
}
