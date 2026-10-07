import Foundation

/// The opaque handle of one supervised child. Web process records use its UUID as their file name.
public struct ProcessToken: Hashable, Sendable, CustomStringConvertible {
    public let id: UUID

    public init(id: UUID = UUID()) { self.id = id }

    public var description: String { id.uuidString }
}
