import Foundation
import JerdWeb

extension SitesModel {
    /// True when the approved HTTPS setup trusts the CA that Caddy made, which can sign any name.
    /// The page then offers the update to Jerd's CA for `.test` names.
    public var needsCAUpdate: Bool {
        guard let setup, let authority, !authority.signsOnlyTestNames, systemSetupState == nil else { return false }
        return setup.certificateSHA256 == authority.fingerprint && setup.installationID == authority.installationID
    }

    /// Makes the new CA, then asks the user to confirm the update with its fingerprint.
    @discardableResult
    public func beginCAUpdate() -> Task<Void, Never>? {
        guard canChangeSystem else { return nil }
        return startWork("Preparing the new Jerd CA…") { [self] in
            do {
                let fingerprint = try await port.prepareCAMigration()
                operation = .idle
                confirmation = .updateCA(fingerprint: fingerprint)
            } catch {
                operation = .failed(message: "The new Jerd CA was not prepared. " + ErrorText.message(for: error))
            }
        }
    }
}
