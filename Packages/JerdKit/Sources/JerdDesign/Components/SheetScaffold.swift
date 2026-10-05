import SwiftUI

/// The one sheet layout: title, optional message, a grouped form, and a footer with Cancel
/// and a confirm button. Escape cancels. Return confirms, except for a destructive confirm,
/// so a destructive step always needs a deliberate click or Space.
/// Cancel stays enabled while the sheet works; it ends the wait, never other work.
public struct SheetScaffold<Content: View>: View {
    private let title: String
    private let message: String?
    private let size: SheetSize
    private let confirmation: SheetConfirmation
    private let workingMessage: String?
    private let cancel: @MainActor () -> Void
    private let content: Content

    /// - Parameter workingMessage: Shows a spinner and this text in the footer while work runs.
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
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title)
                    .textRole(.sheetTitle)
                if let message {
                    Text(message)
                        .textRole(.detail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, columns.textInset)
            .padding(.top, Spacing.section)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            Divider()
            footer
                .padding(.horizontal, columns.sectionInset)
                .padding(.vertical, Spacing.large)
        }
        .frame(width: size.width)
        .frame(minHeight: size.minimumHeight, idealHeight: size.idealHeight)
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
            confirmButton
        }
    }

    @ViewBuilder private var confirmButton: some View {
        let button = Button(role: confirmation.isDestructive ? .destructive : nil) {
            confirmation.perform()
        } label: {
            if confirmation.isDestructive && confirmation.isEnabled {
                Text(confirmation.title).foregroundStyle(.red)
            } else {
                Text(confirmation.title)
            }
        }
        .disabled(!confirmation.isEnabled)
        if confirmation.usesReturnKey {
            button
                .keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}
