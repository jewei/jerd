import Foundation
import JerdFoundation

/// Chooses the CA of this installation. An installation with the CA that Caddy made keeps it
/// until the migration retires it; every other installation uses the CA that Jerd makes, which
/// may sign only `.test` names. The choice reads only which root file exists, so a trust check
/// that fails for a moment can never switch to a CA that the user did not approve.
package enum ActiveAuthority {
    /// The legacy CA when its root may exist (an unknown state keeps it), else the constrained CA.
    package static func resolve(_ environment: EnvironmentLayout, installationID: UUID) -> LocalAuthority {
        usesLegacy(environment) ? .installation(installationID) : .constrainedInstallation(installationID)
    }

    /// The root certificate of the active CA.
    package static func rootCertificateFile(_ environment: EnvironmentLayout) -> URL {
        usesLegacy(environment) ? environment.legacyRootCertificateFile : environment.constrainedRootCertificateFile
    }

    private static func usesLegacy(_ environment: EnvironmentLayout) -> Bool {
        FileProbe.presence(at: environment.legacyRootCertificateFile) != .absent
    }
}
