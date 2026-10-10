import Foundation
import JerdTunnels
import JerdWeb
import Observation

/// The draft of the tunnel editor sheet. The token is write-only: an edit starts with an empty
/// token field, and Cancel and Save clear what the user typed.
@MainActor
@Observable
public final class TunnelEditorModel: Identifiable {
    /// The example local address, shown in the empty address field.
    public static let defaultOrigin = "http://127.0.0.1:8000"

    public let id = UUID()
    public let original: TunnelRegistration?
    public var name: String
    public var hostname: String
    public var token = ""
    public var metricsPort: String
    /// The linked site, or nil for a local address.
    public var siteID: UUID?
    /// The local address, used when no site is chosen. A new draft starts empty, so Jerd never
    /// publishes an address that the user did not enter.
    public var originURL: String
    /// Who sets the route. A new draft uses Jerd.
    public var routing: TunnelRouting
    /// The saved "Connect when Jerd opens". `connectsOnLaunch` is what the sheet shows.
    public var startOnLaunch: Bool
    public var restartOnFailure: Bool
    /// The route mode that the user confirmed, so a change of mode asks again.
    private var checkedRouting: TunnelRouting?
    /// A failed save or port suggestion, shown inline in the sheet.
    public var failure: String?
    /// The registered sites that a route can point to.
    public let sites: [Site]

    public init(tunnel: TunnelRegistration?, sites: [Site], suggestedPort: UInt16? = nil) {
        original = tunnel
        name = tunnel?.name ?? ""
        hostname = tunnel?.hostname ?? ""
        metricsPort = (tunnel?.metricsPort ?? suggestedPort).map(String.init) ?? ""
        siteID = tunnel?.siteID
        originURL = tunnel?.originURL ?? ""
        routing = tunnel?.routing ?? .local
        startOnLaunch = tunnel?.startOnLaunch ?? false
        restartOnFailure = tunnel?.restartOnFailure ?? true
        self.sites = sites
    }

    public var isNew: Bool { original == nil }

    /// The confirmation of the current route mode (`TunnelRouteCopy.check`). Save needs it in
    /// both modes: a dashboard route can point anywhere, and a dashboard tunnel ignores a Jerd route.
    public var routeChecked: Bool {
        get { checkedRouting == routing }
        set { checkedRouting = newValue ? routing : nil }
    }

    /// The text of the route confirmation.
    public var routeCheckTitle: String { TunnelRouteCopy.check(routing) }

    /// False for a Jerd route to a Jerd site (`TunnelRegistration.canConnectOnLaunch`).
    public var canConnectOnLaunch: Bool { TunnelRegistration.canConnectOnLaunch(routing: routing, siteID: siteID) }

    /// "Connect when Jerd opens", always off when the route cannot connect at launch.
    public var connectsOnLaunch: Bool {
        get { startOnLaunch && canConnectOnLaunch }
        set { startOnLaunch = newValue }
    }
    public var title: String { isNew ? "Add Cloudflare Tunnel" : "Edit Cloudflare Tunnel" }

    /// True when the linked site was removed after this registration was saved.
    public var isSiteMissing: Bool {
        siteID.map { id in !sites.contains { $0.id == id } } ?? false
    }

    /// The port as a number above 1023, or nil.
    public var parsedPort: UInt16? {
        UInt16(metricsPort.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 1_023 ? $0 : nil }
    }

    /// The registration that Save sends: a trimmed name and a lower-case hostname, and an
    /// origin only without a site.
    public var registration: TunnelRegistration? {
        guard let port = parsedPort else { return nil }
        return TunnelRegistration(
            id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), siteID: siteID,
            originURL: siteID == nil ? address : nil, startOnLaunch: connectsOnLaunch,
            restartOnFailure: restartOnFailure, metricsPort: port, routing: routing)
    }

    /// The trimmed address, or nil when the field is empty.
    private var address: String? {
        let trimmed = originURL.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True while a Jerd route has no destination yet. Save then asks for the address, as for
    /// any empty field, instead of showing a broken rule.
    private var needsAddress: Bool { routing == .local && siteID == nil && address == nil }

    /// The first broken rule of the filled fields, inline in the sheet. Empty fields say nothing.
    public var validationMessage: String? {
        guard !metricsPort.isEmpty else { return nil }
        guard let registration else { return "Enter a metrics port from 1024 to 65535." }
        guard !registration.name.isEmpty, !registration.hostname.isEmpty, !needsAddress else { return nil }
        do {
            try registration.validate()
            return nil
        } catch {
            return ErrorText.message(for: error)
        }
    }

    /// Every rule holds: a valid registration with a destination, a token for a new tunnel, an
    /// existing site, and the route confirmation.
    public var canSave: Bool {
        guard let registration, !registration.name.isEmpty, !registration.hostname.isEmpty, !needsAddress else {
            return false
        }
        return validationMessage == nil && routeChecked && !isSiteMissing
            && (!isNew || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Why Save is off, or nil. A broken rule and a failure have their own message.
    public var saveRequirement: String? {
        guard !canSave, failure == nil, validationMessage == nil else { return nil }
        var fields = [(name, "a name"), (hostname, "a public hostname")]
        if isNew { fields.append((token, "a tunnel token")) }
        fields.append((metricsPort, "a metrics port"))
        if routing == .local && siteID == nil { fields.append((originURL, "a local address")) }
        let missing = SaveRequirement.missing(fields)
        if !missing.isEmpty { return SaveRequirement.enter(missing) }
        if isSiteMissing { return "The linked site was removed. To save, choose a destination." }
        return "To save, select “\(routeCheckTitle)” at the end of this form."
    }

    /// The token that Save sends: nil keeps the saved one.
    public var tokenToSave: String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Forgets the typed token.
    public func clearToken() {
        token = ""
    }
}
