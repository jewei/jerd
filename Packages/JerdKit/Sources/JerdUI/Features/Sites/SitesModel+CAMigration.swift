import Foundation
import JerdWeb

extension SitesModel {
    /// True when the approved, applied HTTPS setup trusts the CA that Caddy made, which can sign
    /// any name. The page then offers the update to Jerd's CA for `.test` names.
    public var needsCAUpdate: Bool {
        guard let setup, let authority, !authority.signsOnlyTestNames, systemSetupState == nil,
            setup.hostsConfigured, setup.trustConfigured
        else { return false }
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

    /// Replaces the CA, then starts again the sites that ran, also after a failed update, like
    /// Start does. A failed update and a failed start each say what failed.
    func updateCA(_ step: SitesConfirmation) -> Task<Void, Never>? {
        let previous = environment.siteIDs
        return startWork(step.workingMessage) { [self] in
            var failure: AppAlert?
            do {
                try await port.migrateCA()
            } catch is CancellationError {
            } catch {
                failure = AppAlert(title: "The CA Update Did Not Finish", message: ErrorText.message(for: error))
            }
            if !previous.isEmpty {
                operation = .working(message: "Starting the sites again…", canStop: false)
                do {
                    try requireStartable(previous)
                    accept(try await port.run(previous))
                } catch {
                    failure =
                        failure
                        ?? AppAlert(
                            title: "The Sites Did Not Start Again", message: ErrorText.message(for: error))
                }
            }
            operation = .idle
            if let failure { shell.alert(failure) }
        }
    }
}
