import SwiftUI

/// A small borderless copy button whose spoken name includes what it copies.
public struct CopyButton: View {
    private let subject: String
    private let perform: @MainActor () -> Void

    /// - Parameter subject: What the button copies, for example "Inbox URL".
    public init(subject: String, perform: @escaping @MainActor () -> Void) {
        self.subject = subject
        self.perform = perform
    }

    public var body: some View {
        Button {
            perform()
        } label: {
            Image(systemName: "doc.on.doc")
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Copy \(subject)")
        .accessibilityLabel("Copy \(subject)")
        .accessibilityIdentifier(identifier)
    }

    /// The identifier for UI tests, from the subject, for example `copy.inbox-url`.
    var identifier: String { AccessibilityIdentifier.make("copy", subject) }
}
