import Foundation
import JerdFoundation

extension SystemSetupGateway {
    /// Jerd's CA for `.test` names that would replace the CA that Caddy made. It is made when it
    /// is missing; the legacy CA stays active until `migrateCA()` succeeds.
    public func prepareCAMigration() throws -> InstallationAuthority {
        let installationID = try InstallationIdentity(environment: environment).readOrCreate()
        let authority = try provisioner.provisionConstrained(installationID: installationID)
        return InstallationAuthority(installationID: installationID, fingerprint: authority.fingerprint)
    }

    /// Stops the run, retires the folder of the legacy CA so that Jerd's CA becomes active, and
    /// asks the helper to replace the CA. After an error the helper is asked again: when it
    /// already trusts the new CA (a reply that got lost), the update is done; otherwise the folder
    /// moves back, so the app and the helper always name the same CA. The retired folder is kept,
    /// never deleted.
    public func migrateCA() async throws {
        let installationID = try InstallationIdentity(environment: environment).readOrCreate()
        let status = try await system.status()
        let legacy = try InstallationAuthority.read(environment)
        guard let legacy, !legacy.signsOnlyTestNames, status.certificateSHA256 == legacy.fingerprint else {
            throw JerdError.unavailable("This HTTPS setup has no CA to update. Check the HTTPS setup again.")
        }
        let new = try provisioner.provisionConstrained(installationID: installationID)
        await coordinator.halt()
        let retired = try retireLegacyAuthority()
        do {
            try await system.replaceCA(
                HTTPSRegistration(
                    installationID: installationID, hostnames: status.hostnames, certificateDER: new.der,
                    trustPolicy: status.trustPolicy))
        } catch {
            // A status that cannot be read counts as "not replaced": the legacy CA comes back.
            if (try? await system.status())?.certificateSHA256 == new.fingerprint { return }
            try restore(retired, after: error)
            throw error
        }
    }

    /// Retires the legacy CA when the helper trusts no CA and has nothing to recover, for example
    /// after Remove System Setup. A recovery could trust the legacy CA again, so it keeps the CA.
    func retireUntrustedLegacyAuthority() async throws {
        guard let legacy = try InstallationAuthority.read(environment), !legacy.signsOnlyTestNames else { return }
        let status = try await system.status()
        guard status.certificateSHA256 == nil, !status.hasPendingRecovery else { return }
        guard await coordinator.runningPlan() == nil else {
            throw JerdError.unavailable("Stop the environment before preparing a missing CA.")
        }
        _ = try retireLegacyAuthority()
    }

    /// Moves the retired folder back. A failed move names the folder and keeps the first error.
    private func restore(_ retired: URL, after error: any Error) throws {
        do {
            try FileManager.default.moveItem(
                at: retired, to: environment.authorityDirectory(EnvironmentLayout.legacyAuthorityID))
        } catch let moveError {
            throw JerdError.partialChange(
                "The CA update failed (\(FailureDetail.describe(error))), and Jerd could not move \(retired.path) "
                    + "back to pki/authorities/jerd (\(FailureDetail.describe(moveError))). Move it back, then start "
                    + "the sites again.")
        }
    }

    /// Moves `pki/authorities/jerd` to `pki/authorities/jerd-retired-<UTC time>`.
    private func retireLegacyAuthority() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let retired = environment.authorityDirectory("jerd-retired-\(formatter.string(from: Date()))")
        try FileManager.default.moveItem(
            at: environment.authorityDirectory(EnvironmentLayout.legacyAuthorityID), to: retired)
        return retired
    }
}
