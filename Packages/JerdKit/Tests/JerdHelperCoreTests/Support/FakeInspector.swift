import Darwin
import Foundation
import JerdFoundation
import JerdSystem
import os

@testable import JerdHelperCore

/// Reads the trust that `FakeConsent` applied.
struct FakeInspector: CertificateTrustInspecting {
    let consent: FakeConsent

    func isInstalled(_ trust: CertificateTrust) throws -> Bool {
        consent.trusted.withLock { $0[trust.certificate.der] } == trust.consentRequest
    }
}
