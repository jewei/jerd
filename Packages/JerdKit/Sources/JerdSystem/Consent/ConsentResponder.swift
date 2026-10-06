import Foundation
import Security

/// The app's reverse-call object. The helper asks it to set or remove admin trust of the Jerd CA.
///
/// A request is refused at once with `errSecAuthFailed` when it is too large, does not decode, or is
/// outside the open consent scope. Accepted work runs off the calling thread, because macOS can show
/// an authentication prompt. Reply codes: `errSecAuthFailed` (refused or not a certificate),
/// `errSecParam` (invalid hostnames), otherwise the Security status. Removing absent trust succeeds.
public final class ConsentResponder: NSObject, JerdTrustConsentProtocol, Sendable {
    private let gate: ConsentGate
    private let settings: any TrustSettingsApplying

    public init(gate: ConsentGate, settings: any TrustSettingsApplying = AdminTrustSettings()) {
        self.gate = gate
        self.settings = settings
    }

    public func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void) {
        guard request.count < HelperWireProtocol.consentLimit,
            let change = try? JSONDecoder().decode(TrustConsentRequest.self, from: request), gate.allows(change)
        else {
            reply(errSecAuthFailed)
            return
        }
        let settings = settings
        DispatchQueue.global(qos: .userInitiated).async {
            reply(Self.apply(change, with: settings))
        }
    }

    static func apply(_ change: TrustConsentRequest, with settings: any TrustSettingsApplying) -> OSStatus {
        guard SecCertificateCreateWithData(nil, change.certificateDER as CFData) != nil else { return errSecAuthFailed }
        guard let hostnames = change.hostnames else {
            let status = settings.removeAdminTrust(certificateDER: change.certificateDER)
            return status == errSecItemNotFound ? errSecSuccess : status
        }
        guard let validated = try? ValidatedHostnames(hostnames) else { return errSecParam }
        return settings.setAdminTrust(
            certificateDER: change.certificateDER, scope: TrustScope(policy: change.policy, hostnames: validated))
    }
}
