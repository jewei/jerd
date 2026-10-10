import Foundation

/// The rules for site hostnames: lowercase DNS labels under the reserved `.test` top-level domain.
public enum HostnamePolicy {
    /// The longest hostname, in UTF-8 bytes.
    public static let maximumLength = 253
    /// The longest label, in UTF-8 bytes.
    public static let maximumLabelLength = 63
    /// The largest set of hostnames for one HTTPS setup.
    public static let maximumSetCount = 256

    /// Validates one hostname and returns it in lowercase.
    ///
    /// Rules: no surrounding whitespace, at most 253 bytes, ends in `.test`, at least two labels,
    /// and every label has 1–63 bytes of `a-z`, `0-9`, or `-`, without a hyphen at either end.
    public static func validate(_ text: String) throws -> Hostname {
        let host = text.lowercased()
        guard host == text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            host.utf8.count <= maximumLength, host.hasSuffix(".test")
        else { throw JerdError.invalid("Use a hostname ending in .test, without spaces or a port.") }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isValidLabel) else {
            throw JerdError.invalid("Use letters a–z, digits, and internal hyphens in hostname labels.")
        }
        return Hostname(checked: host)
    }

    /// Validates 1 to 256 hostnames that are unique after lowercasing, and returns them sorted.
    public static func validateSet(_ texts: [String]) throws -> [Hostname] {
        guard (1...maximumSetCount).contains(texts.count) else {
            throw JerdError.invalid("Select between 1 and 256 site hostnames for HTTPS setup.")
        }
        let hosts = try texts.map(validate)
        guard Set(hosts).count == hosts.count else { throw JerdError.invalid("Each site needs a unique hostname.") }
        return hosts.sorted()
    }

    /// Suggests a valid hostname from a folder name, for example "My Folder" → `my-folder.test`.
    ///
    /// The name is transliterated to Latin, stripped of diacritics, split at every character that
    /// is not an ASCII letter or digit, joined with hyphens, and cut to 63 characters.
    public static func suggest(folderName: String) -> Hostname {
        let latin = (folderName.applyingTransform(.toLatin, reverse: false) ?? folderName)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = latin.lowercased().split { !$0.isASCII || !($0.isLetter || $0.isNumber) }
        let label = String(parts.joined(separator: "-").prefix(maximumLabelLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return Hostname(checked: (label.isEmpty ? "project" : label) + ".test")
    }

    /// DNS syntax only, for names outside `.test`: at most 253 bytes and two or more labels that
    /// follow the label rule of `validate(_:)`. It checks no reserved name.
    package static func isDNSName(_ text: String) -> Bool {
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        return text.utf8.count <= maximumLength && labels.count >= 2 && labels.allSatisfy(isValidLabel)
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        !label.isEmpty && label.utf8.count <= maximumLabelLength && label.first != "-" && label.last != "-"
            && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
}
