import Foundation
import JerdFoundation

/// A CA replacement changes only the CA, and only to Jerd's CA that may sign only `.test` names.
/// The helper checks it before a replacement, and again when it reads the journal of one. The old
/// CA may be the CA that Caddy made (the migration) or an earlier Jerd CA (a rotation, for example
/// after a lost key); either way the result may sign only `.test` names.
enum CAReplacementRule {
    static func require(_ next: RegistrationRecord, replacing previous: RegistrationRecord) throws {
        guard next.ownerUID == previous.ownerUID, next.installationID == previous.installationID,
            next.hostnames == previous.hostnames, next.trustPolicy == previous.trustPolicy
        else {
            throw JerdError.invalid(
                "A CA replacement must keep the owner, the installation, the hostnames, and the trust policy.")
        }
        guard !next.hasSameCertificate(as: previous) else {
            throw JerdError.invalid("The new CA is the same as the current CA.")
        }
        guard try NameConstraintsInspection.inspect(certificate: next.certificateDER) == .limitedToTest else {
            throw JerdError.invalid("Only a Jerd CA that may sign only .test names can replace the current CA.")
        }
    }
}
