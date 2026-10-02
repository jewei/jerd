import Foundation

public struct ManagedRuntime: Identifiable, Sendable {
    public let kind: RuntimeKind
    public let version: String
    public let releaseVersion: String
    public let archiveSHA256: String
    public let directory: URL
    public let executable: URL
    public let secondaryExecutable: URL?
    public var id: String { "\(kind.rawValue)-\(releaseVersion)-\(archiveSHA256)" }
    public func matches(_ release: RuntimeRelease) -> Bool {
        kind == release.kind && releaseVersion == release.version && release.sha256 == archiveSHA256
    }
}

public struct RuntimeInstallProgress: Sendable {
    public let message: String
    public let fraction: Double?
    init(_ message: String, _ fraction: Double? = nil) { self.message = message; self.fraction = fraction }
}

/// Downloads and stages immutable runtime directories. Activation is a separate operation.
public actor RuntimeInstaller {
    private struct Receipt: Codable {
        let schemaVersion: Int
        let kind: RuntimeKind
        let version: String
        let releaseVersion: String
        let archiveSHA256: String
        let executable: String
        let secondaryExecutable: String?
        let files: [String: String]
    }
    public let directory: URL
    private var busy = false
    private let commands: any CommandRunning
    public init(directory: URL, commands: any CommandRunning = LocalCommandRunner()) { self.directory = directory; self.commands = commands }

    public func installed() throws -> [ManagedRuntime] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { folder in
                guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("update-receipt.json").path) else { return nil }
                return try record(readReceipt(folder), at: folder)
            }
    }

    public func companions() throws -> CLICompanions {
        try JSONDecoder().decode(CLICompanions.self, from: Data(contentsOf: directory.deletingLastPathComponent()
            .appendingPathComponent("runtimes/cli-tools.json")))
    }

    public func activateCompanion(_ runtime: ManagedRuntime) throws {
        guard runtime.kind == .composer || runtime.kind == .laravel else { throw JerdError.invalid("This runtime is not a CLI companion.") }
        let old = try companions()
        let next = CLICompanions(
            composerPath: runtime.kind == .composer ? runtime.executable.path : old.composerPath,
            laravelPath: runtime.kind == .laravel ? runtime.executable.path : old.laravelPath,
            composerVersion: runtime.kind == .composer ? runtime.version : old.composerVersion,
            laravelVersion: runtime.kind == .laravel ? runtime.version : old.laravelVersion)
        try PrivateFiles.write(JSONEncoder().encode(next), to: directory.deletingLastPathComponent().appendingPathComponent("runtimes/cli-tools.json"))
    }

    public func install(_ release: RuntimeRelease, php: DevelopmentRuntime?, companions: CLICompanions?,
                        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void = { _ in }) async throws -> ManagedRuntime {
        guard !busy else { throw JerdError.unavailable("Wait for the current runtime installation to finish.") }
        busy = true; defer { busy = false }
        try release.validate()
        try PrivateFiles.directory(directory)
        if let installed = try existing(release) { return installed }
        let staging = directory.appendingPathComponent(".install-\(UUID())")
        try PrivateFiles.directory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("payload")
        try PrivateFiles.directory(payload)
        let archive = staging.appendingPathComponent("download")
        let hash: String
        if release.kind == .laravel {
            progress(.init("Installing Laravel dependencies…"))
            try await prepareLaravel(release, payload: payload, staging: staging, php: php, companions: companions)
            hash = try RuntimeDownload.digest(payload.appendingPathComponent("composer.lock"))
        } else {
            progress(.init("Downloading \(release.kind.title) \(release.version)…", 0))
            try await RuntimeDownload.file(release.url, to: archive, limit: release.size) {
                progress(.init("Downloading \(release.kind.title) \(release.version)…", $0))
            }
            progress(.init("Verifying download…"))
            hash = try RuntimeDownload.digest(archive)
            if let expected = release.sha256 {
                guard hash == expected else { throw JerdError.invalid("The runtime download failed its SHA-256 check.") }
            } else {
                guard release.kind == .mysql else { throw JerdError.invalid("The runtime download has no verification method.") }
                let signature = staging.appendingPathComponent("signature.asc")
                try await RuntimeDownload.file(URL(string: release.url.absoluteString + ".asc")!, to: signature, limit: 16_384)
                try MySQLSignature.verify(archive: archive, armoredSignature: Data(contentsOf: signature))
            }
            try Task.checkCancellation()
            progress(.init(release.kind == .redis ? "Building Redis with the local compiler…" : "Preparing runtime files…"))
            try await prepare(release, archive: archive, payload: payload, staging: staging)
        }
        let target = directory.appendingPathComponent(Self.directoryName(kind: release.kind, version: release.version, digest: hash))
        if FileManager.default.fileExists(atPath: target.path) {
            let receipt = try readReceipt(target)
            guard receipt.kind == release.kind, receipt.releaseVersion == release.version, receipt.archiveSHA256 == hash else {
                throw JerdError.invalid("The installed build has conflicting metadata. It was preserved.")
            }
            try verify(receipt, at: target)
            return try record(receipt, at: target)
        }
        progress(.init("Checking the installed version…"))
        let (version, executable, secondary) = try await inspect(release, payload: payload, staging: staging, php: php)
        try applyPrivatePermissions(payload)
        let files = try hashes(payload)
        let receipt = Receipt(schemaVersion: 1, kind: release.kind, version: version, releaseVersion: release.version,
            archiveSHA256: hash, executable: executable, secondaryExecutable: secondary, files: files)
        try PrivateFiles.write(JSONEncoder().encode(receipt), to: payload.appendingPathComponent("update-receipt.json"))
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: payload, to: target)
        progress(.init("Installed \(release.kind.title) \(version).", 1))
        return try record(receipt, at: target)
    }

    static func directoryName(kind: RuntimeKind, version: String, digest: String) -> String {
        "\(kind.rawValue)-\(version)-\(CPUArchitecture.current.rawValue)-\(digest)"
    }

    /// A legacy directory may be reused only when its verified archive identity matches.
    /// Different builds remain in separate directories and are never overwritten.
    func existing(_ release: RuntimeRelease) throws -> ManagedRuntime? {
        guard let hash = release.sha256 else { return nil }
        let names = [Self.directoryName(kind: release.kind, version: release.version, digest: hash),
                     "\(release.kind.rawValue)-\(release.version)-\(CPUArchitecture.current.rawValue)"]
        for name in names {
            let target = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let receipt = try readReceipt(target)
            guard receipt.kind == release.kind, receipt.releaseVersion == release.version else {
                throw JerdError.invalid("The installed runtime has conflicting metadata. It was preserved.")
            }
            if receipt.archiveSHA256 != hash { continue }
            try verify(receipt, at: target)
            return try record(receipt, at: target)
        }
        return nil
    }

    private func prepare(_ release: RuntimeRelease, archive: URL, payload: URL, staging: URL) async throws {
        switch release.kind {
        case .php:
            let branch = release.version.split(separator: ".").prefix(2).joined(separator: ".")
            let names: Set<String> = ["php-native-\(branch)", "php-native-fpm-\(branch)", "THIRD-PARTY-NOTICES.txt", "BUILD-INFO.txt"]
            try RuntimeArchive.extract(archive, to: payload) { names.contains($0) }
        case .caddy, .mailpit:
            let names: Set<String> = [release.kind.rawValue, "LICENSE", "README.md"]
            try RuntimeArchive.extract(archive, to: payload) { names.contains($0) }
        case .rustfs:
            try RuntimeArchive.extract(archive, to: payload) { $0 == "rustfs" }
            try await RuntimeDownload.file(URL(string: "https://raw.githubusercontent.com/rustfs/rustfs/\(release.version)/LICENSE")!,
                to: payload.appendingPathComponent("LICENSE"), limit: 1_000_000)
        case .composer:
            try FileManager.default.copyItem(at: archive, to: payload.appendingPathComponent("composer.phar"))
            try await RuntimeDownload.file(URL(string: "https://raw.githubusercontent.com/composer/composer/\(release.version)/LICENSE")!,
                to: payload.appendingPathComponent("LICENSE"), limit: 1_000_000)
        case .mysql:
            let binaries: Set<String> = ["bin/mysqld", "bin/mysql", "bin/mysqladmin", "bin/mysqldump", "LICENSE", "README"]
            try RuntimeArchive.extract(archive, to: payload, stripRoot: true) { name in
                binaries.contains(name) || name.hasPrefix("share/") ||
                (name.hasPrefix("bin/") && name.hasSuffix(".dylib")) || (name.hasPrefix("lib/") && !name.hasSuffix(".a"))
            }
        case .postgresql: try await preparePostgres(archive, payload: payload, staging: staging)
        case .redis:
            let source = staging.appendingPathComponent("redis-source")
            try RuntimeArchive.extract(archive, to: source, stripRoot: true) {
                !$0.hasPrefix("modules/") || $0.hasPrefix("modules/vector-sets/")
            }
            try await run("/usr/bin/xcrun", ["--find", "clang"], in: staging)
            try await run("/usr/bin/make", ["-j\(min(4, ProcessInfo.processInfo.activeProcessorCount))", "MALLOC=libc", "BUILD_TLS=no", "redis-server", "redis-cli"],
                in: source.appendingPathComponent("src"), environment: ["GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                    "GIT_CEILING_DIRECTORIES": staging.path], timeout: .seconds(900))
            try PrivateFiles.directory(payload.appendingPathComponent("bin"))
            for name in ["redis-server", "redis-cli"] {
                try FileManager.default.copyItem(at: source.appendingPathComponent("src/\(name)"), to: payload.appendingPathComponent("bin/\(name)"))
            }
            for name in ["COPYING", "LICENSE.txt", "REDISCONTRIBUTIONS.txt"] where FileManager.default.fileExists(atPath: source.appendingPathComponent(name).path) {
                try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: payload.appendingPathComponent(name))
            }
            try copyTree(source.appendingPathComponent("deps"), to: payload.appendingPathComponent("build-dependency-notices"), allowedRoot: source) {
                !["o", "a", "so", "dylib"].contains($0.pathExtension)
            }
        case .laravel: break
        }
    }

    private func prepareLaravel(_ release: RuntimeRelease, payload: URL, staging: URL, php: DevelopmentRuntime?, companions: CLICompanions?) async throws {
        guard let php, let companions else { throw JerdError.unavailable("Install PHP and Composer before the Laravel installer.") }
        let document: [String: Any] = ["require": ["laravel/installer": release.version],
            "config": ["allow-plugins": false, "secure-http": true, "preferred-install": "dist", "notify-on-install": false]]
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]), to: payload.appendingPathComponent("composer.json"))
        let home = staging.appendingPathComponent("composer-home")
        try PrivateFiles.directory(home)
        try await run(php.cliPath, ["-n", companions.composerPath, "update", "--no-dev", "--no-plugins", "--no-scripts", "--prefer-dist", "--no-interaction", "--no-progress"],
            in: payload, environment: ["COMPOSER_HOME": home.path, "COMPOSER_CACHE_DIR": home.appendingPathComponent("cache").path,
                "COMPOSER_NO_INTERACTION": "1", "PHP_INI_SCAN_DIR": "", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"], timeout: .seconds(900))
    }

    func preparePostgres(_ archive: URL, payload: URL, staging: URL) async throws {
        let mount = staging.appendingPathComponent("volume")
        do {
            try await run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, archive.path], in: staging)
            let app = mount.appendingPathComponent("Postgres.app")
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], in: staging)
            let version = app.appendingPathComponent("Contents/Versions/18")
            for name in ["bin", "lib", "share"] {
                try copyTree(version.appendingPathComponent(name), to: payload.appendingPathComponent(name), allowedRoot: version) { $0.pathExtension != "a" }
            }
            try FileManager.default.copyItem(at: app.appendingPathComponent("Contents/Resources/Credits.rtf"), to: payload.appendingPathComponent("PostgresApp-Credits.rtf"))
            try await run("/usr/bin/hdiutil", ["detach", mount.path], in: staging)
        } catch {
            // Detach also on cancellation. The cleanup task must not inherit cancellation.
            let cleanup = Task.detached { [commands] in
                _ = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    arguments: ["detach", mount.path], directory: staging), timeout: .seconds(30))
            }
            _ = await cleanup.result
            throw error
        }
    }

    private func inspect(_ release: RuntimeRelease, payload: URL, staging: URL, php: DevelopmentRuntime?) async throws -> (String, String, String?) {
        let path: String, arguments: [String]
        switch release.kind {
        case .php:
            let branch = release.version.split(separator: ".").prefix(2).joined(separator: ".")
            let cli = "php-native-\(branch)", fpm = "php-native-fpm-\(branch)"
            let runtime = try await DevelopmentRuntimeProvider().inspectPHP(cli: payload.appendingPathComponent(cli),
                fpm: payload.appendingPathComponent(fpm), workDirectory: staging)
            guard runtime.version == release.version else { throw JerdError.invalid("The downloaded PHP version does not match the release.") }
            return (runtime.version, cli, fpm)
        case .caddy:
            let runtime = try await DevelopmentRuntimeProvider().inspectCaddy(binary: payload.appendingPathComponent("caddy"), workDirectory: staging)
            guard runtime.version.split(separator: " ").first == "v\(release.version)" else { throw JerdError.invalid("The Caddy version does not match the release.") }
            return (release.version, "caddy", nil)
        case .mysql: path = "bin/mysqld"; arguments = ["--no-defaults", "--version"]
        case .postgresql: path = "bin/postgres"; arguments = ["--version"]
        case .redis: path = "bin/redis-server"; arguments = ["--version"]
        case .mailpit: path = "mailpit"; arguments = ["version", "--no-release-check"]
        case .rustfs: path = "rustfs"; arguments = ["--version"]
        case .composer: path = "composer.phar"; arguments = ["--version", "--no-ansi", "--no-plugins"]
        case .laravel: path = "vendor/laravel/installer/bin/laravel"; arguments = ["--version", "--no-ansi"]
        }
        let executable = payload.appendingPathComponent(path)
        let output: String
        if release.kind == .composer || release.kind == .laravel {
            guard let php else { throw JerdError.unavailable("Select a PHP runtime before installing CLI tools.") }
            output = try await run(php.cliPath, ["-n", executable.path] + arguments, in: staging)
        } else {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            output = try await run(executable.path, arguments, in: staging)
        }
        let pattern: String
        switch release.kind {
        case .postgresql: pattern = "PostgreSQL\\) ([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)"
        case .redis: pattern = "Redis server v=([0-9]+\\.[0-9]+\\.[0-9]+)"
        default: pattern = "(?<![0-9])" + NSRegularExpression.escapedPattern(for: release.version) + "(?![0-9.])"
        }
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = output as NSString
        guard let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: ns.length)) else {
            throw JerdError.invalid("The installed \(release.kind.title) did not report the expected version.")
        }
        let version = release.kind == .postgresql || release.kind == .redis ? ns.substring(with: match.range(at: 1)) : release.version
        guard release.kind == .postgresql || version == release.version else { throw JerdError.invalid("The runtime version does not match the release.") }
        return (version, path, nil)
    }

    @discardableResult private func run(_ executable: String, _ arguments: [String], in folder: URL,
                                       environment: [String: String] = [:], timeout: Duration = .seconds(60)) async throws -> String {
        let result = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: executable), arguments: arguments,
            directory: folder, environment: environment), timeout: timeout)
        guard result.status == 0 else { throw JerdError.process("Runtime preparation failed: \(result.diagnosticOutput.suffix(3000))") }
        return result.output
    }

    private func copyTree(_ source: URL, to destination: URL, allowedRoot: URL, selected: (URL) -> Bool) throws {
        let root = allowedRoot.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var visited = Set<String>(), count = 0
        func copy(_ from: URL, _ to: URL) throws {
            try Task.checkCancellation()
            let resolved = from.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathComponents.starts(with: root) else { throw JerdError.invalid("A runtime file link leaves its directory.") }
            let info = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            count += 1
            guard count <= 100_000 else { throw JerdError.invalid("The runtime contains too many files.") }
            if info.isDirectory == true {
                guard visited.insert(resolved.path).inserted else { throw JerdError.invalid("The runtime contains a directory link cycle.") }
                defer { visited.remove(resolved.path) }
                try PrivateFiles.directory(to)
                for child in try FileManager.default.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil) {
                    try copy(child, to.appendingPathComponent(child.lastPathComponent))
                }
            } else if selected(from) {
                guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 512_000_000 else { throw JerdError.invalid("A runtime file is invalid.") }
                try FileManager.default.copyItem(at: resolved, to: to)
            }
        }
        try copy(source, destination)
    }

    private func hashes(_ payload: URL) throws -> [String: String] {
        let payload = payload.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: payload, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]) else {
            throw JerdError.invalid("The runtime files cannot be read.")
        }
        var files: [String: String] = [:]
        for case let file as URL in enumerator {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            guard info.isSymbolicLink != true else { throw JerdError.invalid("The prepared runtime contains a symbolic link.") }
            if info.isDirectory == true { continue }
            guard info.isRegularFile == true, files.count < 50_000 else { throw JerdError.invalid("The prepared runtime has invalid or too many files.") }
            let components = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard components.starts(with: payload.pathComponents) else { throw JerdError.invalid("A runtime file leaves its directory.") }
            let name = components.dropFirst(payload.pathComponents.count).joined(separator: "/")
            files[name] = try RuntimeDownload.digest(file)
        }
        guard !files.isEmpty else { throw JerdError.invalid("The runtime package is empty.") }
        return files
    }
    private func applyPrivatePermissions(_ payload: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: payload, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]) else {
            throw JerdError.invalid("The runtime files cannot be read.")
        }
        for case let file as URL in enumerator {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            guard info.isSymbolicLink != true else { throw JerdError.invalid("The prepared runtime contains a symbolic link.") }
            if info.isDirectory == true {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            } else {
                guard info.isRegularFile == true else { throw JerdError.invalid("The prepared runtime contains an invalid file.") }
                let executable = FileManager.default.isExecutableFile(atPath: file.path)
                try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: file.path)
            }
        }
    }
    private func readReceipt(_ folder: URL) throws -> Receipt {
        let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw JerdError.invalid("The runtime directory is invalid.") }
        let file = folder.appendingPathComponent("update-receipt.json")
        guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max < 8_000_000 else { throw JerdError.invalid("The update receipt is too large.") }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: file))
        guard receipt.schemaVersion == 1, RuntimeVersion(receipt.version) != nil, RuntimeVersion(receipt.releaseVersion) != nil,
              RuntimeDownload.validSHA256(receipt.archiveSHA256),
              !receipt.files.isEmpty, receipt.files.count <= 50_000, receipt.files[receipt.executable] != nil,
              receipt.secondaryExecutable.map({ receipt.files[$0] != nil }) ?? true,
              receipt.files.allSatisfy({ safePath($0.key) && RuntimeDownload.validSHA256($0.value) }) else {
            throw JerdError.invalid("The update receipt is invalid. Existing files were preserved.")
        }
        return receipt
    }
    private func record(_ receipt: Receipt, at folder: URL) throws -> ManagedRuntime {
        guard ["\(receipt.kind.rawValue)-\(receipt.releaseVersion)-\(CPUArchitecture.current.rawValue)",
               Self.directoryName(kind: receipt.kind, version: receipt.releaseVersion, digest: receipt.archiveSHA256)].contains(folder.lastPathComponent) else {
            throw JerdError.invalid("The installed runtime directory does not match its receipt.")
        }
        return ManagedRuntime(kind: receipt.kind, version: receipt.version, releaseVersion: receipt.releaseVersion, archiveSHA256: receipt.archiveSHA256, directory: folder,
            executable: folder.appendingPathComponent(receipt.executable), secondaryExecutable: receipt.secondaryExecutable.map { folder.appendingPathComponent($0) })
    }
    private func verify(_ receipt: Receipt, at folder: URL) throws {
        let actual = try hashes(folder).filter { $0.key != "update-receipt.json" }
        guard actual == receipt.files else {
            let changed = Set(actual.keys).union(receipt.files.keys).filter { actual[$0] != receipt.files[$0] }.sorted().prefix(8)
            throw JerdError.invalid("The installed runtime changed: \(changed.joined(separator: ", ")). Existing files were preserved.")
        }
    }
    private func safePath(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.contains("\\") &&
        name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
