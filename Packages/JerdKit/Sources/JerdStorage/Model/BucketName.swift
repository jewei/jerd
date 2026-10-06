import Foundation

/// The bucket name rules of Jerd: the general-purpose S3 rules without reserved names.
///
/// A name has 3 to 63 bytes of `a-z`, `0-9`, `.`, and `-`; it starts and ends with a letter or
/// digit; it has no `..`, `.-`, or `-.`; it is not an IPv4 address; and it has no reserved
/// prefix or suffix.
public enum BucketName {
    static let reservedPrefixes = ["xn--", "sthree-", "amzn-s3-demo-"]
    static let reservedSuffixes = ["-s3alias", "--ol-s3", ".mrap", "--x-s3", "--table-s3"]

    /// True when `name` follows every rule.
    public static func isValid(_ name: String) -> Bool {
        (3...63).contains(name.utf8.count)
            && matches(name, "^[a-z0-9][a-z0-9.-]*[a-z0-9]$")
            && !["..", ".-", "-."].contains(where: name.contains)
            && !matches(name, "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
            && !reservedPrefixes.contains(where: name.hasPrefix)
            && !reservedSuffixes.contains(where: name.hasSuffix)
    }

    /// - Throws: `.invalid` with the rules when `name` breaks one.
    public static func validate(_ name: String) throws {
        guard isValid(name) else { throw StorageMessages.bucketNameInvalid }
    }

    private static func matches(_ name: String, _ pattern: String) -> Bool {
        name.range(of: pattern, options: .regularExpression) != nil
    }
}
