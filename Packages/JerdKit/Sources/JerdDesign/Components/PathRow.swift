import SwiftUI

/// A form row for a file or folder: the label, the path under it (middle truncation, full
/// path as a tooltip, selectable), and a button that shows the item in Finder.
public struct PathRow: View {
    private let label: String
    private let path: String
    private let revealTitle: String
    private let reveal: @MainActor () -> Void

    /// - Parameter reveal: Shows the item in Finder. The caller owns the workspace call.
    public init(
        _ label: String, path: String, revealTitle: String = "Show in Finder",
        reveal: @escaping @MainActor () -> Void
    ) {
        self.label = label
        self.path = path
        self.revealTitle = revealTitle
        self.reveal = reveal
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(label)
                    .textRole(.rowTitle)
                Text(path)
                    .textRole(.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
                    .accessibilityLabel("Path")
                    .accessibilityValue(path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(revealTitle, action: reveal)
                .fixedSize()
                .help("\(revealTitle): \(label)")
                .accessibilityLabel("\(revealTitle), \(label)")
                .accessibilityIdentifier(AccessibilityIdentifier.make("path", label, "reveal"))
        }
        .accessibilityElement(children: .contain)
    }
}
