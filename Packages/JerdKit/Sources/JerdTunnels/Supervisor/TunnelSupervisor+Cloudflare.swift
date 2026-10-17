import Foundation
import JerdFoundation

extension TunnelSupervisor {
    /// Creates a tunnel and its DNS record in Cloudflare, then saves the registration with the
    /// new token. It never connects. When the save fails, Jerd deletes what it created.
    public func create(_ registration: TunnelRegistration, in zone: CloudflareZone) async throws {
        try requireLoaded()
        try beginEdit()
        defer { editing = false }
        try requireCreatable(registration, in: zone)
        let provision = try await cloudflare.provision(
            hostname: registration.hostname, zone: zone, tunnelName: Self.tunnelName(registration.hostname))
        var created = registration
        created.cloudflare = provision.record
        let next = configuration.upserting(created)
        do {
            try next.validate()
            try await secrets.write(provision.token.value, id: created.id)
            try store.save(next)
        } catch {
            try await undoCreate(provision.record, id: created.id, after: error)
        }
        configuration = next
        lifecycles[created.id] = .idle
    }

    /// Deletes the DNS record and the tunnel that Jerd created, then removes the registration.
    /// When Cloudflare refuses, the registration stays, so the user can try again.
    public func removeFromCloudflare(id: UUID) async throws {
        try requireLoaded()
        try beginEdit()
        defer { editing = false }
        guard !isActive(id) else { throw JerdError.unavailable(TunnelMessage.stopBeforeRemove) }
        guard let record = configuration.registration(id)?.cloudflare else {
            throw JerdError.invalid(CloudflareMessage.notCreatedByJerd)
        }
        try await cloudflare.deprovision(record)
        try await removeRegistration(id)
    }

    /// The name of the tunnel in Cloudflare, so the user can see which tunnels Jerd made.
    static func tunnelName(_ hostname: String) -> String { "jerd-\(hostname)" }

    /// A new registration with a Jerd route, a hostname in the zone, and settings that still validate.
    private func requireCreatable(_ registration: TunnelRegistration, in zone: CloudflareZone) throws {
        guard configuration.registration(registration.id) == nil, registration.cloudflare == nil,
            registration.routing == .local,
            registration.hostname == zone.name || registration.hostname.hasSuffix(".\(zone.name)")
        else { throw JerdError.invalid(TunnelMessage.invalidConfiguration) }
        guard zone.isCertificateCovered(registration.hostname) else {
            throw JerdError.invalid(CloudflareMessage.subdomainLevel)
        }
        try registration.validate()
        try configuration.upserting(registration).validate()
    }

    /// Removes the token and deletes the new Cloudflare resources, then rethrows `failure`. When
    /// a step fails, the message names what is left.
    private func undoCreate(
        _ record: CloudflareTunnelRecord, id: UUID, after failure: any Error
    ) async throws
        -> Never
    {
        var problems: [String] = []
        do { try await secrets.remove(id: id) } catch { problems.append(FailureDetail.describe(error)) }
        do { try await cloudflare.deprovision(record) } catch { problems.append(FailureDetail.describe(error)) }
        guard problems.isEmpty else {
            throw JerdError.partialChange(
                CloudflareMessage.undoFailed(FailureDetail.describe(failure), detail: problems.joined(separator: " ")))
        }
        throw failure
    }
}
