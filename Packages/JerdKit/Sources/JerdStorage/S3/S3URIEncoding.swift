import Foundation

/// The URI encoding of S3 Signature Version 4: every byte except `A-Z a-z 0-9 - . _ ~` becomes
/// `%XX` with uppercase hexadecimal digits. A path also keeps `/`.
enum S3URIEncoding {
    /// Encodes `value` byte by byte. With `keepingSlash`, `/` stays as it is (for paths).
    static func encode(_ value: String, keepingSlash: Bool = false) -> String {
        var encoded = ""
        for byte in value.utf8 {
            if isUnreserved(byte) || (keepingSlash && byte == UInt8(ascii: "/")) {
                encoded.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }

    /// The canonical query: each name and value encoded, sorted by name and then value, joined
    /// as `name=value` with `&`. An empty value gives `name=`.
    static func canonicalQuery(_ items: [String: String]) -> String {
        let pairs: [(name: String, value: String)] = items.map { (encode($0.key), encode($0.value)) }
        let sorted = pairs.sorted { left, right in
            left.name == right.name ? left.value < right.value : left.name < right.name
        }
        return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || [45, 46, 95, 126].contains(byte)
    }
}
