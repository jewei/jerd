import Foundation
import JerdFoundation

extension TunnelSupervisor {
    /// Adds or changes a registration. A new token replaces the saved one; nil keeps it.
    ///
    /// Save never connects. When the settings cannot be saved, the token that was there before
    /// is put back (or the new one is removed).
    public func save(_ registration: TunnelRegistration, token text: String? = nil) async throws {
        try requireLoaded()
        try beginEdit()
        defer { editing = false }
        guard !isActive(registration.id) else { throw JerdError.unavailable(TunnelMessage.stopBeforeEdit) }
        try registration.validate()
        let next = configuration.upserting(registration)
        try next.validate()
        let previous = try await secrets.read(id: registration.id)
        if let text {
            let token = try TunnelToken(text)
            try await requireUnique(token, except: registration.id)
            try await secrets.write(token.value, id: registration.id)
        } else if previous == nil {
            throw JerdError.invalid(TunnelMessage.tokenRequired)
        }
        do {
            try store.save(next)
        } catch {
            guard text != nil else { throw error }
            try await restoreToken(previous, id: registration.id, after: error)
        }
        configuration = next
        lifecycles[registration.id] = .idle
    }

    /// Removes a registration and its token. The instance folder and its logs stay, and no remote
    /// resource changes. An unknown ID does nothing.
    public func remove(id: UUID) async throws {
        try requireLoaded()
        try beginEdit()
        defer { editing = false }
        guard !isActive(id) else { throw JerdError.unavailable(TunnelMessage.stopBeforeRemove) }
        guard configuration.registration(id) != nil else { return }
        let previous = try await secrets.read(id: id)
        var next = configuration
        next.tunnels.removeAll { $0.id == id }
        try await secrets.remove(id: id)
        do {
            try store.save(next)
        } catch {
            try await restoreToken(previous, id: id, after: error)
        }
        configuration = next
        lifecycles[id] = nil
    }

    /// Refuses a second registration for the same remote tunnel, also with a rotated token.
    private func requireUnique(_ token: TunnelToken, except id: UUID) async throws {
        for other in configuration.tunnels where other.id != id {
            guard let saved = try await secrets.read(id: other.id) else { continue }
            if TunnelToken.tunnelID(of: saved) == token.tunnelID {
                throw JerdError.invalid(TunnelMessage.duplicateTunnel)
            }
        }
    }

    /// Puts the earlier token back after a failed settings save, then rethrows the save error.
    /// When the token cannot be put back, both problems are reported.
    private func restoreToken(_ previous: String?, id: UUID, after failure: any Error) async throws -> Never {
        do {
            if let previous {
                try await secrets.write(previous, id: id)
            } else {
                try await secrets.remove(id: id)
            }
        } catch {
            throw JerdError.partialChange(
                "\(FailureDetail.describe(failure)) The earlier tunnel token could not be restored: "
                    + FailureDetail.describe(error))
        }
        throw failure
    }
}
