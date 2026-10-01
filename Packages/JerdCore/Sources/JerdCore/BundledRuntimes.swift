import Foundation
import CryptoKit

/// Installs the initial payload while preserving runtime selections and later updates.
public actor BundledRuntimes {
    private struct Pins: Decodable {
        let schemaVersion: Int
        let architecture: String
        let artifacts: [Artifact]
    }
    private struct Artifact: Decodable {
        let name: String
        let tag: String
        let sha256: String
        let files: [String]
    }
    private struct Receipt: Decodable {
        let schemaVersion: Int
        let archiveSHA256: String
        let fileSHA256: [String: String]
    }

    public init() {}

    public func needsBootstrap(configuration: AppConfiguration, directory: URL) throws -> Bool {
        let file = directory.appendingPathComponent("cli-tools.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return true }
        // Decode before deciding on setup. A corrupt record must never be reset.
        let companions = try JSONDecoder().decode(CLICompanions.self, from: Data(contentsOf: file))
        return configuration.runtimes.isEmpty || configuration.caddy == nil ||
            companions.composerVersion == nil || companions.laravelVersion == nil
    }

    public func install(from source: URL, into directory: URL) async throws -> (DevelopmentRuntime, CaddyRuntime) {
        let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: source.appendingPathComponent("pins.json")))
        guard pins.schemaVersion == 1, pins.architecture == CPUArchitecture.current.rawValue,
              Set(pins.artifacts.map(\.name)) == ["php", "caddy", "composer", "laravel-installer"], pins.artifacts.count == 4 else {
            throw JerdError.unavailable("The bundled development runtimes do not support this Mac.")
        }
        try PrivateFiles.directory(directory)
        var installed: [String: URL] = [:]
        for entry in pins.artifacts {
            guard !entry.tag.isEmpty, !entry.tag.contains(".."),
                  entry.tag.utf8.allSatisfy({ $0 == 45 || $0 == 46 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
                  entry.files.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }) else {
                throw JerdError.invalid("The bundled runtime manifest is invalid.")
            }
            let origin = source.appendingPathComponent(entry.name)
            let receiptData = try Data(contentsOf: origin.appendingPathComponent("jerd-receipt.json"))
            let receipt = try JSONDecoder().decode(Receipt.self, from: receiptData)
            let tree = entry.name == "laravel-installer"
            guard receipt.schemaVersion == 1, receipt.archiveSHA256 == entry.sha256,
                  tree ? receipt.fileSHA256["composer.lock"] == entry.sha256 : Set(receipt.fileSHA256.keys) == Set(entry.files),
                  receipt.fileSHA256.count < 20_000,
                  receipt.fileSHA256.keys.allSatisfy({ name in
                      !name.hasPrefix("/") && name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
                  }) else {
                throw JerdError.invalid("The bundled runtime receipt does not match its manifest.")
            }
            let target = directory.appendingPathComponent("\(entry.name)-\(entry.tag)-\(pins.architecture)")
            if FileManager.default.fileExists(atPath: target.path) {
                try verify(target, receipt: receipt)
            } else {
                try verify(origin, receipt: receipt)
                let staging = directory.appendingPathComponent(".install-\(UUID().uuidString)")
                try PrivateFiles.directory(staging)
                defer { try? FileManager.default.removeItem(at: staging) }
                for name in receipt.fileSHA256.keys {
                    let file = staging.appendingPathComponent(name)
                    try PrivateFiles.directory(file.deletingLastPathComponent())
                    try FileManager.default.copyItem(at: origin.appendingPathComponent(name), to: file)
                    let executable = name == "caddy" || name.hasPrefix("php-native")
                    try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: file.path)
                }
                try PrivateFiles.write(receiptData, to: staging.appendingPathComponent("jerd-receipt.json"))
                try verify(staging, receipt: receipt)
                try FileManager.default.moveItem(at: staging, to: target)
            }
            installed[entry.name] = target
        }
        guard let php = installed["php"], let caddy = installed["caddy"], let composer = installed["composer"],
              let laravel = installed["laravel-installer"] else { throw JerdError.invalid("The runtime payload is incomplete.") }
        let companions = CLICompanions(composerPath: composer.appendingPathComponent("composer.phar").path,
            laravelPath: laravel.appendingPathComponent("vendor/laravel/installer/bin/laravel").path,
            composerVersion: pins.artifacts.first { $0.name == "composer" }?.tag,
            laravelVersion: pins.artifacts.first { $0.name == "laravel-installer" }?.tag)
        let companionFile = directory.appendingPathComponent("cli-tools.json")
        if FileManager.default.fileExists(atPath: companionFile.path) {
            let existing = try JSONDecoder().decode(CLICompanions.self, from: Data(contentsOf: companionFile))
            // Fill version fields for an existing bootstrap record, without changing selections.
            let current = CLICompanions(composerPath: existing.composerPath, laravelPath: existing.laravelPath,
                composerVersion: existing.composerVersion ?? (existing.composerPath == companions.composerPath ? companions.composerVersion : nil),
                laravelVersion: existing.laravelVersion ?? (existing.laravelPath == companions.laravelPath ? companions.laravelVersion : nil))
            try PrivateFiles.write(try JSONEncoder().encode(current), to: companionFile)
        } else {
            try PrivateFiles.write(try JSONEncoder().encode(companions), to: companionFile)
        }
        let provider = DevelopmentRuntimeProvider()
        let work = directory.appendingPathComponent("inspection")
        let runtime = try await provider.inspectPHP(cli: php.appendingPathComponent("php-native-8.5"),
                                                   fpm: php.appendingPathComponent("php-native-fpm-8.5"), workDirectory: work)
        let server = try await provider.inspectCaddy(binary: caddy.appendingPathComponent("caddy"), workDirectory: work)
        return (runtime, server)
    }

    private func verify(_ directory: URL, receipt: Receipt) throws {
        let directoryInfo = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard directoryInfo.isSymbolicLink != true, directoryInfo.isDirectory == true else {
            throw JerdError.invalid("The runtime directory is invalid.")
        }
        for (name, expected) in receipt.fileSHA256 {
            let file = directory.appendingPathComponent(name)
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) < 512_000_000,
                  try RuntimeDownload.digest(file) == expected else {
                throw JerdError.invalid("Runtime verification failed for \(name). The existing file was preserved.")
            }
        }
    }
}
