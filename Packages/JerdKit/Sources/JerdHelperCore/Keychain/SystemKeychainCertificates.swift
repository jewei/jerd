import Foundation
import JerdFoundation
import Security

/// The Jerd CA in `/Library/Keychains/System.keychain`. Only the helper (root) uses it.
///
/// Deletion finds candidates by normalized issuer and serial number, keeps only the item whose full
/// bytes equal the recorded CA, requires exactly one, and deletes that keychain-backed reference.
struct SystemKeychainCertificates: KeychainCertificateStoring {
    static let path = "/Library/Keychains/System.keychain"

    func add(_ der: Data) throws -> KeychainAddOutcome {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate, kSecValueRef as String: try certificate(der),
            kSecUseKeychain as String: try keychain(),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem { return .alreadyPresent }
        try SecurityStatus.check(status, "add the Jerd root certificate")
        return .added
    }

    func deleteExact(_ der: Data) throws {
        let expected = try certificate(der)
        guard let issuer = SecCertificateCopyNormalizedIssuerSequence(expected),
            let serial = SecCertificateCopySerialNumberData(expected, nil)
        else { throw JerdError.invalid("The recorded certificate has no issuer or serial number.") }
        let keychain = try keychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate, kSecAttrIssuer as String: issuer,
            kSecAttrSerialNumber as String: serial, kSecMatchSearchList as String: [keychain],
            kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        try SecurityStatus.check(status, "find the stored Jerd certificate")
        guard let candidates = result as? [SecCertificate] else {
            throw JerdError.unavailable("The stored certificate lookup returned an invalid result.")
        }
        let matches = candidates.filter { SecCertificateCopyData($0) as Data == der }
        guard matches.count == 1 else {
            throw JerdError.invalid(
                "The stored certificate does not uniquely match Jerd's recorded CA. It was preserved.")
        }
        let deletion: [String: Any] = [
            kSecClass as String: kSecClassCertificate, kSecMatchItemList as String: matches,
            kSecMatchSearchList as String: [keychain],
        ]
        try SecurityStatus.check(SecItemDelete(deletion as CFDictionary), "remove the Jerd root certificate")
    }

    /// `SecKeychainOpen` is deprecated, but it is the only API that names the system keychain file
    /// for `SecItemAdd` and the search list. The symbol is resolved at run time, so the build has no
    /// deprecation warning; the call is the same.
    private func keychain() throws -> SecKeychain {
        typealias Open = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<SecKeychain?>) -> OSStatus
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecKeychainOpen") else {
            throw JerdError.unavailable("The system keychain is unavailable.")
        }
        var keychain: SecKeychain?
        let status = Self.path.withCString { unsafeBitCast(symbol, to: Open.self)($0, &keychain) }
        try SecurityStatus.check(status, "open the system keychain")
        guard let keychain else { throw JerdError.unavailable("The system keychain is unavailable.") }
        return keychain
    }

    private func certificate(_ der: Data) throws -> SecCertificate {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw JerdError.invalid("The stored CA certificate is invalid.")
        }
        return certificate
    }
}
