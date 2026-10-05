import SwiftUI

/// The one sheet layout: title, optional message, a grouped form, and a footer with Cancel
/// and a confirm button. Escape cancels. Return confirms, except for a destructive confirm,
/// so a destructive step always needs a deliberate click or Space.
/// The sheet is as tall as its content, between the minimum and maximum of its `SheetSize`.
/// Cancel stays enabled while the sheet works; it ends the wait, never other work.
public struct SheetScaffold<Content: View>: View {
    private let title: String
    private let message: String?
    private let size: SheetSize
    private let confirmation: SheetConfirmation
    private let workingMessage: String?
    private let cancel: @MainActor () -> Void
    private let content: Content
    /// The measured height of the form content, on macOS 15 and later.
    @State private var formContentHeight: CGFloat?

    /// - Parameter workingMessage: Shows a spinner and this text in the footer while work runs.
    ///   The confirm button is disabled while it shows.
    public init(
        _ title: String, message: String? = nil, size: SheetSize = .standard, confirmation: SheetConfirmation,
        workingMessage: String? = nil, cancel: @escaping @MainActor () -> Void, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.message = message
        self.size = size
        self.confirmation = confirmation
        self.workingMessage = workingMessage
        self.cancel = cancel
        self.content = content()
    }

    public var body: some View {
        let columns = PageMetrics.columns(forWidth: size.width)
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.horizontal, columns.textInset)
                .padding(.top, Spacing.section)
            form
            Divider()
            footer
                .padding(.horizontal, columns.sectionInset)
                .padding(.vertical, Spacing.large)
        }
        .frame(width: size.width)
        // No ideal height: the sheet takes the height of its content, within these limits.
        .frame(minHeight: size.minimumHeight, maxHeight: size.maximumHeight)
    }

    /// Confirm waits for running work, so one click cannot start the same work twice.
    var isConfirmEnabled: Bool {
        confirmation.isEnabled && workingMessage == nil
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(title)
                .textRole(.sheetTitle)
            if let message {
                Text(message)
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var form: some View {
        let form = Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        if #available(macOS 15, *) {
            // A form scrolls, so its own ideal height is not its content height on every macOS
            // version. Measure the content and ask for exactly that height.
            form
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, height in
                    formContentHeight = height
                }
                .frame(idealHeight: formContentHeight)
        } else {
            form
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.small) {
            if let workingMessage {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(workingMessage)
                Text(workingMessage)
                    .textRole(.detail)
                    .lineLimit(2)
            }
            Spacer(minLength: Spacing.small)
            Button(confirmation.cancelTitle, role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(ifPresent: confirmation.cancelIdentifier)
            SheetConfirmButton(confirmation: confirmation, isEnabled: isConfirmEnabled)
        }
    }
}
