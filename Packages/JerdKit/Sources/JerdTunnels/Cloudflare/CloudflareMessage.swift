/// Every user-visible message of the Cloudflare account and the tunnels that Jerd creates.
package enum CloudflareMessage {
    package static let notConnected = "Connect Cloudflare with an API token before you create a tunnel."
    /// The API token permissions that Create needs, in the words of the Cloudflare token page.
    package static let tokenPermissions =
        "Account › Cloudflare Tunnel › Edit, Zone › DNS › Edit, and Zone › Zone › Read"
    package static let tokenFormat = "Paste the Cloudflare API token without spaces."
    package static let tokenRejected =
        "Cloudflare rejected the API token. Create a token with the permissions that Jerd lists, then connect again."
    package static let noZones =
        "The API token cannot edit any domain. Give it Zone: DNS: Edit and Zone: Read for your domain."
    package static let subdomainLevel =
        "Enter the subdomain without a dot, for example dev. Cloudflare's free certificate covers only one level "
        + "below the domain."
    package static let invalidRecord = "The saved Cloudflare record of this tunnel is invalid."
    package static let invalidResponse = "Cloudflare sent a response that Jerd cannot read. Try again later."
    package static let hostnameFixed =
        "Jerd created this tunnel with its DNS record, so its public hostname cannot change. Create a new tunnel instead."
    package static let routingFixed =
        "Jerd created this tunnel as locally managed, so Jerd sets its route. Keep the route set by Jerd."
    package static let otherTunnelToken = "This token belongs to another tunnel. Paste a token of this tunnel."
    package static let notCreatedByJerd = "Jerd did not create this tunnel, so it cannot delete it in Cloudflare."
    package static func unreachable(_ detail: String) -> String {
        "Jerd cannot reach the Cloudflare API: \(detail)"
    }
    package static func failed(_ detail: String) -> String {
        "Cloudflare refused the request: \(detail)"
    }
    package static func missingPermission(_ detail: String) -> String {
        "Cloudflare refused the request because the API token lacks a permission: \(detail). Edit the token in "
            + "Cloudflare so that it has \(tokenPermissions), then try again."
    }
    package static func recordExists(_ hostname: String) -> String {
        "\(hostname) already has a DNS record in Cloudflare. Jerd never replaces a record. Choose another name, "
            + "or delete the record in Cloudflare first."
    }
    package static func tunnelExists(_ tunnelName: String) -> String {
        "Cloudflare already has a tunnel named \(tunnelName), for example from an earlier Create whose answer was "
            + "lost. Delete \(tunnelName) in the Cloudflare dashboard, then create the tunnel again."
    }
    package static func undoFailed(_ failure: String, detail: String) -> String {
        "\(failure) Jerd could not fully undo the new tunnel: \(detail) Check the tunnel and its DNS record in "
            + "the Cloudflare dashboard."
    }
    package static func rollbackFailed(_ failure: String, tunnelName: String, detail: String) -> String {
        "\(failure) Jerd could not delete the new tunnel \(tunnelName) in Cloudflare: \(detail) "
            + "Delete it in the Cloudflare dashboard."
    }
}
