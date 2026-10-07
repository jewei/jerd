import Foundation

/// Turns an error into the one message that a page shows.
enum ErrorText {
    /// The user message of `error`: the `LocalizedError` description, else the system text.
    static func message(for error: any Error) -> String {
        if let description = (error as? any LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}
