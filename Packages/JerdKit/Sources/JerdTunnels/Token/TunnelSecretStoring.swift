import Foundation

/// Keeps tunnel tokens outside settings files, one per registration ID.
public protocol TunnelSecretStoring: Sendable {
    /// The saved token text, or nil when none is saved.
    func read(id: UUID) async throws -> String?
    /// Saves or replaces the token text of `id`.
    func write(_ token: String, id: UUID) async throws
    /// Removes the token of `id`. A missing token is not an error.
    func remove(id: UUID) async throws
}
