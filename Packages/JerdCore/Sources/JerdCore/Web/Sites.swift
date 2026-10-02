import Foundation

public protocol ProjectFileSystem: Sendable {
    func canonicalDirectory(_ path: String) throws -> String
    func isFile(_ path: String) -> Bool
}

public struct LocalProjectFileSystem: ProjectFileSystem {
    public init() {}
    public func canonicalDirectory(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw JerdError.invalid("Use an absolute directory path without control characters.")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw JerdError.invalid("Directory does not exist: \(path)")
        }
        return url.path
    }
    public func isFile(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
    }
}

public struct DocumentRootSuggestion: Equatable, Sendable {
    public let path: String
    public let isLaravel: Bool
    public let requiresConfirmation: Bool
}

public enum Hostname {
    public static func validatedSet(_ values: [String]) throws -> [String] {
        guard !values.isEmpty, values.count <= 256 else {
            throw JerdError.invalid("Select between 1 and 256 site hostnames for HTTPS setup.")
        }
        let hosts = try values.map(validate)
        guard Set(hosts).count == hosts.count else { throw JerdError.invalid("Each site needs a unique hostname.") }
        return hosts.sorted()
    }

    public static func suggestion(folderName: String) -> String {
        let latin = (folderName.applyingTransform(.toLatin, reverse: false) ?? folderName)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = latin.lowercased().split(whereSeparator: { character in
            !character.isASCII || !(character.isLetter || character.isNumber)
        })
        let label = String(parts.joined(separator: "-").prefix(63)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (label.isEmpty ? "project" : label) + ".test"
    }

    public static func validate(_ value: String) throws -> String {
        let host = value.lowercased()
        guard host == value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              host.utf8.count <= 253, host.hasSuffix(".test") else {
            throw JerdError.invalid("Use a hostname ending in .test, without spaces or a port.")
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { throw JerdError.invalid("Use letters a–z, digits, and internal hyphens in hostname labels.") }
        return host
    }
}

public enum HostsFile {
    public static let begin = "# BEGIN JERD"
    public static let end = "# END JERD"

    // Read-only registration check. The helper separately validates the exact owned section.
    public static func hasConflict(hostname: String, contents: String) -> Bool {
        var owned = false
        for line in contents.components(separatedBy: .newlines) {
            if line == begin { owned = true; continue }
            if line == end { owned = false; continue }
            let fields = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .split(whereSeparator: { $0.isWhitespace })
            guard fields.count > 1 else { continue }
            if fields.dropFirst().contains(where: { $0.lowercased() == hostname.lowercased() }) {
                if !owned || !["127.0.0.1", "::1"].contains(String(fields[0])) { return true }
            }
        }
        return false
    }
}

public struct SiteValidator: Sendable {
    private let files: any ProjectFileSystem
    public init(files: any ProjectFileSystem = LocalProjectFileSystem()) { self.files = files }

    public func suggestDocumentRoot(projectPath: String) throws -> DocumentRootSuggestion {
        let project = try files.canonicalDirectory(projectPath)
        let base = URL(fileURLWithPath: project)
        let publicPath = base.appendingPathComponent("public").path
        let laravel = files.isFile(base.appendingPathComponent("artisan").path) &&
            files.isFile(base.appendingPathComponent("composer.json").path) &&
            files.isFile(base.appendingPathComponent("public/index.php").path)
        return DocumentRootSuggestion(path: laravel ? publicPath : project,
                                      isLaravel: laravel, requiresConfirmation: !laravel)
    }

    public func validate(_ draft: Site, existing: [Site], hostsContents: String = "",
                         documentRootConfirmed: Bool) throws -> Site {
        var site = draft
        site.displayName = site.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.displayName.isEmpty else { throw JerdError.invalid("Enter a site name.") }
        site.hostname = try Hostname.validate(site.hostname)
        site.projectPath = try files.canonicalDirectory(site.projectPath)
        site.documentRoot = try files.canonicalDirectory(site.documentRoot)
        let projectParts = URL(fileURLWithPath: site.projectPath).pathComponents
        let rootParts = URL(fileURLWithPath: site.documentRoot).pathComponents
        guard rootParts.starts(with: projectParts) else {
            throw JerdError.invalid("The document root must be inside the project directory.")
        }
        let suggestion = try suggestDocumentRoot(projectPath: site.projectPath)
        guard documentRootConfirmed || (suggestion.isLaravel && suggestion.path == site.documentRoot) else {
            throw JerdError.invalid("Confirm the document root before saving this site.")
        }
        for other in existing where other.id != site.id {
            guard other.hostname.lowercased() != site.hostname else {
                throw JerdError.invalid("This hostname is already registered.")
            }
            guard other.projectPath != site.projectPath else {
                throw JerdError.invalid("This project directory is already registered.")
            }
        }
        guard !HostsFile.hasConflict(hostname: site.hostname, contents: hostsContents) else {
            throw JerdError.invalid("This hostname has a conflicting /etc/hosts entry. Choose another hostname.")
        }
        return site
    }
}
