import Foundation

/// One copy confirmation, for example "Copied inbox URL". Each value is a new event, even with
/// the same text, so a second copy of the same value restarts the toast and is announced again.
public struct CopyFeedbackMessage: Hashable, Sendable {
    public let text: String
    private let id: UUID

    public init(_ text: String) {
        self.text = text
        self.id = UUID()
    }
}
