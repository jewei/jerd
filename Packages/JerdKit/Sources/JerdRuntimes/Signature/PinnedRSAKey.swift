import Foundation
import JerdFoundation

/// A pinned RSA public key of a publisher, with its OpenPGP v4 fingerprint.
public struct PinnedRSAKey: Sendable, Equatable {
    /// The OpenPGP v4 fingerprint: 40 uppercase hexadecimal characters.
    public let fingerprint: String
    /// The PKCS#1 `RSAPublicKey` DER bytes.
    public let publicKeyDER: Data
    /// The modulus size in bytes. A signature is left-padded with zeros to this size.
    public let modulusBytes: Int
    /// The single message of every verification failure with this key.
    public let failureMessage: String

    public init(fingerprint: String, publicKeyDER: Data, modulusBytes: Int, failureMessage: String) {
        self.fingerprint = fingerprint
        self.publicKeyDER = publicKeyDER
        self.modulusBytes = modulusBytes
        self.failureMessage = failureMessage
    }

    /// Oracle's MySQL release key (RSA-4096) from `RPM-GPG-KEY-mysql-2025`.
    ///
    /// The key file has SHA-256 `a4bcd9f16a53cc763f87b9955dbcdced33c7aa90296b157eb6ceef0f156f4327`.
    public static let mysqlRelease2025 = PinnedRSAKey(
        fingerprint: "BCA43417C3B485DD128EC6D4B7B3B788A8D3785C",
        publicKeyDER: Data(base64Encoded: mysqlPublicKey) ?? Data(),
        modulusBytes: 512,
        failureMessage: "The MySQL publisher signature is invalid or uses an unsupported signing key.")

    /// The base64 PKCS#1 key. A decode failure gives an empty key, which `SecKey` then refuses.
    private static let mysqlPublicKey =
        "MIICCgKCAgEAkoubdJy+vx493dD8LG3Z22Pkqi1CGd7lmUJurbDYb052obzz2QRnZffYlmE7dipl6dCnjdrPaZiypBgG2nED9UaszBZ6B2"
        + "sEjH9Kk1FYwL4ZyOPqszA40zUgavX2t5x5jmMaMJ560ZKYkFDP8g+/yZlRDYMFm+mpGXhmK13IfY3eF1d7fDg+kxs03nU5ItEwza+mGWI"
        + "Qu41JvXyvWbNvfaczl0sUUTRnftx/YG14s6wbuC/95VKzX//6zOzr1fR6O7vWGMgENy9/jgASvRShzYa6YvENHG4b1pA+KAiifmGeeF6zh"
        + "tGE4P2FALOf9//xQEyNbFnbS4yeaUm9KJ1dyyG2q0UzfJQuC3v+ZHd5XKLfSfG9xDFy+afThlu8AX5jVUUlCO+FZsLfr/YMqdB3dJHkQlJ"
        + "/JaP9VdGA/YvdirBPvyKqGE458mv+ZF+NYwfL69Xm5BxbieNOPhuhE3dKMMMauuIyyHLKfxgWRxlNESigKPQ0Sx+66UOz1ZZ8PEwzZTrVr"
        + "eRCZQVxXDy/jYFm6pAAwMgP10jXlpaqJ7z5WH5mrJwBwKTHfTYT0IQu4SU4wogMBvFMlqVfA49OwxxUOcQW5E5yh9jqybYLj6kjWLUwEm7F"
        + "s9PUvLo6Ew1xU9ezWxTNnTCIqtGuFUAd0sx9dx9oqPQm4P08yayRpsIKF4MCAwEAAQ=="

    /// The error of every failure with this key.
    package var failure: JerdError { .invalid(failureMessage) }
}
