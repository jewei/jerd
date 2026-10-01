import Foundation
import Security
import JerdCore

/// Only the installation's validated root is accepted. Trust is limited to TLS
/// for the approved registered hostnames. No subprocess or arbitrary keychain path.
struct SystemCertificateTrust: CertificateTrustManaging {
    var consent: TrustConsentClient? = nil
    func validate(_ der: Data, installationID: UUID) throws {
        _ = try InstallationCertificate.validate(der, installationID: installationID)
    }

    func isInstalled(_ der: Data, hostnames: [String]) throws -> Bool {
        let cert = try certificate(der)
        var settings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(cert, .admin, &settings)
        if status == errSecItemNotFound { return false }
        try check(status, "read Jerd certificate trust")
        guard let entries = settings as? [[String: Any]], entries.count == hostnames.count else { return false }
        var found: Set<String> = []
        for entry in entries {
            guard let hostname = entry[kSecTrustSettingsPolicyString as String] as? String,
                  found.insert(hostname).inserted,
                  (entry[kSecTrustSettingsResult as String] as? NSNumber)?.uint32Value == SecTrustSettingsResult.trustRoot.rawValue,
                  let value = entry[kSecTrustSettingsPolicy as String], CFGetTypeID(value as CFTypeRef) == SecPolicyGetTypeID() else { return false }
            let policy = value as! SecPolicy
            guard let properties = SecPolicyCopyProperties(policy) as NSDictionary?,
                  properties[kSecPolicyOid] as? String == kSecPolicyAppleSSL as String else { return false }
        }
        return found == Set(hostnames)
    }

    func install(_ der: Data, hostnames: [String], replacingOwned: Bool) async throws {
        guard let consent else { throw JerdError.unavailable("The app must approve certificate changes.") }
        let cert = try certificate(der)
        let keychain = try systemKeychain()
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                   kSecValueRef as String: cert, kSecUseKeychain as String: keychain]
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess || (added == errSecDuplicateItem && replacingOwned) else {
            if added == errSecDuplicateItem { throw JerdError.invalid("This CA already exists outside Jerd's tracked setup. It was not changed.") }
            try check(added, "add the Jerd root certificate")
            return
        }
        if replacingOwned, try isInstalled(der, hostnames: hostnames) { return }
        let status = try await consent.change(TrustConsentRequest(certificateDER: der, hostnames: hostnames))
        if status != errSecSuccess {
            if added == errSecSuccess {
                try deleteStoredCertificate(der, keychain: keychain)
            }
            try check(status, "set Jerd certificate trust")
        }
    }

    func remove(_ der: Data) async throws {
        guard let consent else { throw JerdError.unavailable("The app must approve certificate changes.") }
        let status = try await consent.change(TrustConsentRequest(certificateDER: der, hostname: nil))
        if status != errSecItemNotFound { try check(status, "remove Jerd certificate trust") }
        try deleteStoredCertificate(der, keychain: systemKeychain())
    }

    private func deleteStoredCertificate(_ der: Data, keychain: SecKeychain) throws {
        let expected = try certificate(der)
        guard let issuer = SecCertificateCopyNormalizedIssuerSequence(expected),
              let serial = SecCertificateCopySerialNumberData(expected, nil) else {
            throw JerdError.invalid("The recorded certificate has no issuer or serial number.")
        }
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
            kSecAttrIssuer as String: issuer, kSecAttrSerialNumber as String: serial,
            kSecMatchSearchList as String: [keychain], kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        try check(status, "find the stored Jerd certificate")
        guard let candidates = result as? [SecCertificate] else {
            throw JerdError.unavailable("The stored certificate lookup returned an invalid result.")
        }
        let matches = candidates.filter { SecCertificateCopyData($0) as Data == der }
        guard matches.count == 1 else {
            throw JerdError.invalid("The stored certificate does not uniquely match Jerd's recorded CA. It was preserved.")
        }
        // Delete the keychain-backed reference, not a new in-memory certificate.
        // https://developer.apple.com/documentation/security/secitemdelete(_:)
        let deletion: [String: Any] = [kSecClass as String: kSecClassCertificate,
            kSecMatchItemList as String: matches, kSecMatchSearchList as String: [keychain]]
        try check(SecItemDelete(deletion as CFDictionary), "remove the Jerd root certificate")
    }

    private func systemKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        try check(SecKeychainOpen("/Library/Keychains/System.keychain", &keychain), "open the system keychain")
        guard let keychain else { throw JerdError.unavailable("The system keychain is unavailable.") }
        return keychain
    }

    private func certificate(_ data: Data) throws -> SecCertificate {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw JerdError.invalid("The stored CA certificate is invalid.")
        }
        return certificate
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw JerdError.unavailable("Cannot \(operation): \(detail)")
        }
    }
}
