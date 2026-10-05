import Foundation

/// The JSON encoder options of a saved file. They are part of the compatibility contract.
public enum JSONFileFormat: Sendable, Equatable {
    /// `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`: settings files such as
    /// `configuration.json`, `services.json`, and every `settings.json`.
    case settings
    /// `JSONEncoder()` defaults (compact, unsorted keys, escaped slashes): markers,
    /// credentials, journals, receipts, and active-run records.
    case compact

    /// A new encoder with the exact options of this format and default date and data strategies.
    public func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        if self == .settings {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        return encoder
    }
}
