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
    /// asks the helper to replace the CA. A refusal moves the folder back, so the app and the
    /// helper always name the same CA. The retired folder is kept, never deleted.
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
            try FileManager.default.moveItem(
                at: retired, to: environment.authorityDirectory(EnvironmentLayout.legacyAuthorityID))
            throw error
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
