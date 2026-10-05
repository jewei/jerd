import Foundation

/// An inspected PHP CLI and PHP-FPM pair of one version.
///
/// The property names are the saved JSON keys. `inspectedAt` uses the default `Date` coding:
/// seconds since 2001-01-01 as a JSON number.
public struct DevelopmentRuntime: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public let cliPath: String
    public let fpmPath: String
    public let version: String
    public let architectures: [CPUArchitecture]
    public let cliExtensions: [String]
    public let fpmExtensions: [String]
    public let inspectedAt: Date

    public init(
        id: UUID = UUID(), cliPath: String, fpmPath: String, version: String, architectures: [CPUArchitecture],
        cliExtensions: [String], fpmExtensions: [String], inspectedAt: Date = Date()
    ) {
        self.id = id
        self.cliPath = cliPath
        self.fpmPath = fpmPath
        self.version = version
        self.architectures = architectures
        self.cliExtensions = cliExtensions
        self.fpmExtensions = fpmExtensions
        self.inspectedAt = inspectedAt
    }

    /// True when both runtimes serve the same way: every field except `inspectedAt`.
    public func servesLike(_ other: DevelopmentRuntime) -> Bool {
        id == other.id && cliPath == other.cliPath && fpmPath == other.fpmPath && version == other.version
            && architectures == other.architectures && cliExtensions == other.cliExtensions
            && fpmExtensions == other.fpmExtensions
    }
}
