import Foundation
import JerdTunnels

extension TunnelEditorModel {
    /// Why Create is off: first the Cloudflare connection, then the domain, then the destination.
    var createRequirement: String? {
        if isCloudflareConnected != true { return "To create a tunnel, connect Cloudflare with an API token." }
        if zone == nil { return "To create a tunnel, choose a domain." }
        let missing = SaveRequirement.missing(
            [(metricsPort, "a metrics port")] + (siteID == nil ? [(originURL, "a local address")] : []))
        if !missing.isEmpty { return SaveRequirement.enter(missing) }
        if isSiteMissing { return "The linked site was removed. To save, choose a destination." }
        return nil
    }

    /// A subdomain deeper than one level, which Cloudflare's free certificate does not cover.
    var subdomainMessage: String? {
        guard isCreating, let zone, !zone.isCertificateCovered(publicHostname) else { return nil }
        return CloudflareMessage.subdomainLevel
    }

    /// The API token that Connect sends, or nil when the field is empty.
    public var apiTokenToConnect: String? {
        let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Shows the zones of the connected account and keeps a valid selection.
    public func useZones(_ zones: [CloudflareZone]) {
        self.zones = zones
        isCloudflareConnected = true
        if zone == nil { zoneID = zones.first?.id }
    }

    /// Forgets the account after Disconnect.
    public func forgetCloudflare() {
        isCloudflareConnected = false
        zones = []
        zoneID = nil
    }
}
