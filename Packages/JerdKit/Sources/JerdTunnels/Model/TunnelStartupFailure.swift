import Foundation

/// A tunnel that could not connect when Jerd opened. Each failure is kept, so none hides another.
public struct TunnelStartupFailure: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let message: String

    public init(id: UUID, name: String, message: String) {
        self.id = id
        self.name = name
        self.message = message
    }
}
