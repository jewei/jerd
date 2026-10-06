/// The rule for one port that the user types: a whole number from 1024 to 65535. Jerd never
/// asks for a privileged port, because every service runs without root.
enum PortInput {
    static let range: ClosedRange<Int> = 1_024...65_535
    /// The placeholder of every port field.
    static let prompt = "1024–65535"
    static let message = "Enter a port from 1024 to 65535."

    /// The port in `text`, or nil when it is not a whole number in the range. Spaces around the
    /// number are allowed.
    static func parse(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII), let value = Int(trimmed), range.contains(value)
        else { return nil }
        return UInt16(value)
    }
}
