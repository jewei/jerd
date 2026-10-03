import Foundation

public enum RuntimeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case php, caddy, composer, laravel, mysql, postgresql, redis, mailpit, rustfs, cloudflared
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .php: "PHP"; case .caddy: "Caddy"; case .composer: "Composer"; case .laravel: "Laravel installer"
        case .mysql: "MySQL"; case .postgresql: "PostgreSQL"; case .redis: "Redis"; case .mailpit: "Mailpit"; case .rustfs: "RustFS"
        case .cloudflared: "Cloudflare Tunnel"
        }
    }
}

public struct RuntimeVersion: Comparable, Hashable, Sendable {
    public let components: [Int]
    public init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 < 100_000 }) else { return nil }
        components = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct RuntimeRelease: Identifiable, Equatable, Sendable {
    public let kind: RuntimeKind
    public let version: String
    public let url: URL
    public let sha256: String?
    public let size: Int64
    public let source: URL
    public let architecture: CPUArchitecture
    public let minimumOSMajor: Int?
    public var id: String { "\(kind.rawValue)-\(version)" + (sha256.map { "-\($0)" } ?? "") }
    /// PostgreSQL uses the Postgres.app release number until its engine is inspected.
    public var versionLabel: String { kind == .postgresql ? "Postgres.app \(version)" : version }
    public init(kind: RuntimeKind, version: String, url: URL, sha256: String?, size: Int64, source: URL,
                architecture: CPUArchitecture = .current, minimumOSMajor: Int? = nil) {
        self.kind = kind; self.version = version; self.url = url; self.sha256 = sha256; self.size = size; self.source = source
        self.architecture = architecture; self.minimumOSMajor = minimumOSMajor
    }
    func validate() throws {
        guard RuntimeVersion(version) != nil, size > 0, size <= 800_000_000,
              (sha256.map(RuntimeDownload.validSHA256) ?? (kind == .mysql || kind == .laravel)) else {
            throw JerdError.invalid("The update metadata is incomplete or invalid.")
        }
        try RuntimeDownload.validate(url)
        try RuntimeDownload.validate(source)
        guard architecture == .current, minimumOSMajor.map({ ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= $0 }) ?? true else {
            throw JerdError.unavailable("This runtime package is not compatible with this Mac.")
        }
    }
}

public struct RuntimeUpdateCheck: Sendable {
    public let kind: RuntimeKind
    public let releases: [RuntimeRelease]
    public let checkedAt: Date
    public let error: String?
}

public actor RuntimeUpdateCatalog {
    private let metadata = RuntimeMetadata()
    public init() {}
    public func check(_ kind: RuntimeKind) async -> RuntimeUpdateCheck {
        do {
            let releases = try await releases(for: kind)
            for release in releases { try release.validate() }
            guard !releases.isEmpty else { throw JerdError.unavailable("No supported stable macOS package is available from this source.") }
            return RuntimeUpdateCheck(kind: kind, releases: releases.sorted {
                RuntimeVersion($0.version)! > RuntimeVersion($1.version)!
            }, checkedAt: Date(), error: nil)
        } catch { return RuntimeUpdateCheck(kind: kind, releases: [], checkedAt: Date(), error: error.localizedDescription) }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int64
            let digest: String?
        }
    }
    private func github(_ repository: String) async throws -> [GitHubRelease] {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!
        return try JSONDecoder().decode([GitHubRelease].self, from: await metadata.data(url)).filter { !$0.draft && !$0.prerelease }
    }
    private func releases(for kind: RuntimeKind) async throws -> [RuntimeRelease] {
        let arm = CPUArchitecture.current == .arm64
        switch kind {
        case .php, .caddy, .mailpit, .rustfs, .postgresql:
            let repository: String
            switch kind {
            case .php: repository = "lerd-env/php"
            case .caddy: repository = "caddyserver/caddy"
            case .mailpit: repository = "axllent/mailpit"
            case .rustfs: repository = "rustfs/rustfs"
            default: repository = "PostgresApp/PostgresApp"
            }
            let source = URL(string: "https://github.com/\(repository)/releases")!
            return try await github(repository).compactMap { release in
                let version = release.tag_name.replacingOccurrences(of: "php-", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                guard RuntimeVersion(version) != nil else { return nil }
                let name: String
                switch kind {
                case .php: name = "lerd-php-\(version)-darwin-\(arm ? "arm64" : "x86_64").tar.gz"
                case .caddy: name = "caddy_\(version)_mac_\(arm ? "arm64" : "amd64").tar.gz"
                case .mailpit: name = "mailpit-darwin-\(arm ? "arm64" : "amd64").tar.gz"
                case .rustfs: name = "rustfs-macos-\(arm ? "aarch64" : "x86_64")-v\(version).zip"
                default: name = "Postgres-\(version)-18.dmg"
                }
                guard let asset = release.assets.first(where: { $0.name == name }),
                      let digest = asset.digest, digest.hasPrefix("sha256:") else { return nil }
                return RuntimeRelease(kind: kind, version: version, url: asset.browser_download_url,
                    sha256: String(digest.dropFirst(7)), size: asset.size, source: source)
            }
        case .composer:
            struct Versions: Decodable { let stable: [Entry]; struct Entry: Decodable { let version: String; let path: String } }
            let source = URL(string: "https://getcomposer.org/versions")!
            let versions = try JSONDecoder().decode(Versions.self, from: await metadata.data(source))
            guard let entry = versions.stable.first, RuntimeVersion(entry.version) != nil,
                  entry.path == "/download/\(entry.version)/composer.phar" else { throw JerdError.invalid("Composer metadata is invalid.") }
            let url = URL(string: "https://getcomposer.org\(entry.path)")!
            let hash = try await metadata.text(URL(string: url.absoluteString + ".sha256sum")!).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            return [RuntimeRelease(kind: kind, version: entry.version, url: url, sha256: hash, size: 20_000_000, source: source)]
        case .laravel:
            // Composer resolves and verifies dependencies in an isolated staging directory.
            let releases = try await github("laravel/installer")
            guard let latest = releases.first, let version = RuntimeVersion(latest.tag_name) else { return [] }
            let value = version.components.prefix(3).map(String.init).joined(separator: ".")
            return [RuntimeRelease(kind: kind, version: value, url: URL(string: "https://repo.packagist.org/p2/laravel/installer.json")!,
                sha256: nil, size: 8_000_000, source: URL(string: "https://github.com/laravel/installer/releases")!)]
        case .redis:
            let source = URL(string: "https://raw.githubusercontent.com/redis/redis-hashes/master/README")!
            let content = try await metadata.text(source)
            return content.split(whereSeparator: \.isNewline).compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 4, fields[0] == "hash", fields[2] == "sha256",
                      fields[1].hasPrefix("redis-"), fields[1].hasSuffix(".tar.gz") else { return nil }
                let version = String(fields[1].dropFirst(6).dropLast(7))
                guard let parsed = RuntimeVersion(version), parsed.components[0] >= 8 else { return nil }
                return RuntimeRelease(kind: kind, version: version, url: URL(string: "https://download.redis.io/releases/\(fields[1])")!,
                    sha256: String(fields[3]), size: 40_000_000, source: source)
            }
        case .mysql:
            let source = URL(string: "https://dev.mysql.com/downloads/mysql/8.4.html?os=33")!
            let content = try await metadata.text(source)
            return try Self.mysqlReleases(content, architecture: arm ? "arm64" : "x86_64",
                                          majorOS: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        case .cloudflared:
            let url = URL(string: "https://api.github.com/repos/cloudflare/cloudflared/releases?per_page=30")!
            return try Self.cloudflaredReleases(await metadata.data(url), architecture: .current)
        }
    }

    static func cloudflaredReleases(_ data: Data, architecture: CPUArchitecture) throws -> [RuntimeRelease] {
        let name = "cloudflared-darwin-\(architecture == .arm64 ? "arm64" : "amd64").tgz"
        let source = URL(string: "https://github.com/cloudflare/cloudflared/releases")!
        return try JSONDecoder().decode([GitHubRelease].self, from: data).compactMap { release in
            guard !release.draft, !release.prerelease,
                  RuntimeVersion(release.tag_name) != nil,
                  let asset = release.assets.first(where: { $0.name == name }),
                  let digest = asset.digest, digest.hasPrefix("sha256:"),
                  RuntimeDownload.validSHA256(String(digest.dropFirst(7))),
                  asset.browser_download_url.absoluteString ==
                    "https://github.com/cloudflare/cloudflared/releases/download/\(release.tag_name)/\(name)" else { return nil }
            return RuntimeRelease(kind: .cloudflared, version: release.tag_name,
                url: asset.browser_download_url, sha256: String(digest.dropFirst(7)),
                size: asset.size, source: source, architecture: architecture)
        }
    }

    static func mysqlReleases(_ content: String, architecture: String, majorOS: Int) throws -> [RuntimeRelease] {
            let source = URL(string: "https://dev.mysql.com/downloads/mysql/8.4.html?os=33")!
            let regex = try NSRegularExpression(pattern: "mysql-(8\\.4\\.[0-9]+)-macos(1[5-9]|[2-9][0-9])-\(architecture)\\.tar\\.gz")
            let ns = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))
            var seen = Set<String>()
            return matches.compactMap { match in
                let name = ns.substring(with: match.range), version = ns.substring(with: match.range(at: 1))
                guard let minimumOS = Int(ns.substring(with: match.range(at: 2))), majorOS >= minimumOS,
                      seen.insert(version).inserted else { return nil }
                return RuntimeRelease(kind: .mysql, version: version, url: URL(string: "https://cdn.mysql.com/Downloads/MySQL-8.4/\(name)")!,
                    sha256: nil, size: 500_000_000, source: source, minimumOSMajor: minimumOS)
            }
    }
}
