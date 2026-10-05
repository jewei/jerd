import Foundation

/// A database folder that has no registration, for example after Remove. It can be restored
/// when it has no problem and its exact runtime is registered.
public struct RetainedDatabase: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let runtime: DatabaseRuntime?
    public let port: UInt16?
    public let directory: URL
    /// The size of the folder, or nil when it is unknown or the folder has a problem.
    public let bytes: Int64?
    /// Why the folder cannot be restored, or nil.
    public let problem: String?

    public init(
        id: UUID, name: String, runtime: DatabaseRuntime?, port: UInt16?, directory: URL, bytes: Int64?,
        problem: String?
    ) {
        self.id = id
        self.name = name
        self.runtime = runtime
        self.port = port
        self.directory = directory
        self.bytes = bytes
        self.problem = problem
    }

    public var canRestore: Bool { problem == nil && runtime != nil }
}
