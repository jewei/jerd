/// One row of a Connection section. A value that a user pastes into an application has a copy
/// action. A description has none, but its row keeps the copy-button gutter, so the values of
/// all rows end at one edge.
struct ConnectionValue: Identifiable {
    let label: String
    let value: String
    /// Copies the value, or nil for a description.
    let copy: (@MainActor () -> Void)?

    var id: String { label }

    /// A technical value, in the code font, with a copy action.
    static func pasteable(_ label: String, _ value: String, copy: @escaping @MainActor () -> Void) -> Self {
        ConnectionValue(label: label, value: value, copy: copy)
    }

    /// A description for the reader, for example "Path style".
    static func description(_ label: String, _ value: String) -> Self {
        ConnectionValue(label: label, value: value, copy: nil)
    }
}
