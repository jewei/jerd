import Foundation
import JerdFoundation

/// A setup without an earlier registration trusts only Jerd's CA that may sign only `.test` names.
/// An unconstrained CA that the user approved earlier keeps its trust until the CA update.
enum NewTrustRule {
    static func require(_ next: RegistrationRecord) throws {
        guard try NameConstraintsInspection.inspect(certificate: next.certificateDER) == .limitedToTest else {
            throw JerdError.invalid(
                "Jerd trusts a new CA only when it may sign only .test names. Set up HTTPS again, so that "
                    + "Jerd uses its CA for .test names.")
        }
    }
}
