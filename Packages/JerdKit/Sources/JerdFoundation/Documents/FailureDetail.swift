import Foundation

/// Turns an underlying error into one short sentence for a user, without raw decoder dumps.
public enum FailureDetail {
    /// The message of a `JerdError`, a short sentence for a `DecodingError`, or the localized description.
    public static func describe(_ error: any Error) -> String {
        if let error = error as? JerdError { return error.message }
        if let error = error as? DecodingError { return describe(error) }
        return error.localizedDescription
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "A required value is missing: \(path(context.codingPath + [key]))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            "A value has an unexpected type: \(path(context.codingPath))."
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            "The file does not contain valid JSON."
        case .dataCorrupted(let context):
            "A value is invalid: \(path(context.codingPath))."
        @unknown default:
            "The file has an unexpected form."
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        guard !keys.isEmpty else { return "the top level" }
        return keys.map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }
            .joined(separator: ".")
            .replacingOccurrences(of: ".[", with: "[")
    }
}
