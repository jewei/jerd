/// The object identifiers of the certificates that Jerd makes and inspects.
public enum CertificateObjectIdentifier {
    public static let commonName: [UInt64] = [2, 5, 4, 3]
    public static let ecPublicKey: [UInt64] = [1, 2, 840, 10045, 2, 1]
    public static let prime256v1: [UInt64] = [1, 2, 840, 10045, 3, 1, 7]
    public static let ecdsaWithSHA256: [UInt64] = [1, 2, 840, 10045, 4, 3, 2]
    public static let subjectKeyIdentifier: [UInt64] = [2, 5, 29, 14]
    public static let keyUsage: [UInt64] = [2, 5, 29, 15]
    public static let subjectAlternativeName: [UInt64] = [2, 5, 29, 17]
    public static let basicConstraints: [UInt64] = [2, 5, 29, 19]
    public static let nameConstraints: [UInt64] = [2, 5, 29, 30]
    public static let authorityKeyIdentifier: [UInt64] = [2, 5, 29, 35]
    public static let extendedKeyUsage: [UInt64] = [2, 5, 29, 37]
    public static let serverAuthentication: [UInt64] = [1, 3, 6, 1, 5, 5, 7, 3, 1]
}
