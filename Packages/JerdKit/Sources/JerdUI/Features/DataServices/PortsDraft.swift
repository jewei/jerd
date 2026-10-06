/// The two port fields of the mail or storage ports sheet. Both ports must be valid and differ.
public struct PortsDraft: Equatable, Sendable {
    static let message = "Enter two different ports from 1024 to 65535."

    public var first: String
    public var second: String

    public init(first: UInt16, second: UInt16) {
        self.first = String(first)
        self.second = String(second)
    }

    public init(first: String, second: String) {
        self.first = first
        self.second = second
    }

    /// Both ports, or nil when either is invalid or they are equal.
    public var ports: (first: UInt16, second: UInt16)? {
        guard let first = PortInput.parse(first), let second = PortInput.parse(second), first != second else {
            return nil
        }
        return (first, second)
    }

    /// The inline message under the fields, or nil when the ports can be saved.
    public var issue: String? {
        ports == nil ? Self.message : nil
    }
}
