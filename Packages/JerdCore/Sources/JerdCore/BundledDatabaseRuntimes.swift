import Foundation
import CryptoKit

public actor BundledDatabaseRuntimes {
    private struct Pins: Decodable {
        let schemaVersion: Int
        let architecture: String
        let artifacts: [Artifact]
    }
    private struct Artifact: Decodable {
        let id: String
        let engine: DatabaseEngine
        let version: String
        let sha256: String
    }
    private struct FileRecord: Decodable {
        let sha256: String
        let executable: Bool
    }
    private struct Receipt: Decodable {
        let schemaVersion: Int
        let archiveSHA256: String
        let files: [String: FileRecord]
    }
    public init() {}

    public func install(from source: URL, into directory: URL) throws -> [DatabaseRuntime] {
        let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: source.appendingPathComponent("pins.json")))
        guard pins.schemaVersion == 1, pins.architecture == CPUArchitecture.current.rawValue,
              pins.artifacts.count <= 20, Set(pins.artifacts.map(\.id)).count == pins.artifacts.count else {
            throw JerdError.unavailable("The database runtime bundle does not support this Mac.")
        }
        try PrivateFiles.directory(directory)
        var installed: [DatabaseRuntime] = []
        for artifact in pins.artifacts {
            guard DatabaseConfiguration.safeIdentifier(artifact.id), DatabaseConfiguration.safeIdentifier(artifact.version) else {
                throw JerdError.invalid("The database runtime manifest is invalid.")
            }
            let origin = source.appendingPathComponent(artifact.id)
            let receiptData = try Data(contentsOf: origin.appendingPathComponent("jerd-receipt.json"))
            let receipt = try JSONDecoder().decode(Receipt.self, from: receiptData)
            guard receipt.schemaVersion == 1, receipt.archiveSHA256 == artifact.sha256,
                  !receipt.files.isEmpty, receipt.files.count <= 20_000,
                  receipt.files["bin/\(artifact.engine.serverName)"]?.executable == true,
                  receipt.files["bin/\(artifact.engine.clientName)"]?.executable == true,
                  receipt.files.keys.allSatisfy(Self.safeRelativePath) else {
                throw JerdError.invalid("The database runtime receipt is invalid.")
            }
            let target = directory.appendingPathComponent(artifact.id)
            if FileManager.default.fileExists(atPath: target.path) {
                try verify(target, receipt: receipt)
            } else {
                try verify(origin, receipt: receipt)
                let staging = directory.appendingPathComponent(".install-\(UUID().uuidString)")
                try PrivateFiles.directory(staging)
                defer { try? FileManager.default.removeItem(at: staging) }
                for (name, record) in receipt.files {
                    let file = staging.appendingPathComponent(name)
                    try PrivateFiles.directory(file.deletingLastPathComponent())
                    try FileManager.default.copyItem(at: origin.appendingPathComponent(name), to: file)
                    try FileManager.default.setAttributes([.posixPermissions: record.executable ? 0o700 : 0o600], ofItemAtPath: file.path)
                }
                try PrivateFiles.write(receiptData, to: staging.appendingPathComponent("jerd-receipt.json"))
                try verify(staging, receipt: receipt)
                try FileManager.default.moveItem(at: staging, to: target)
            }
            installed.append(DatabaseRuntime(id: artifact.id, engine: artifact.engine, version: artifact.version, path: target.path))
        }
        return installed
    }

    private static func safeRelativePath(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
        name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func verify(_ directory: URL, receipt: Receipt) throws {
        let root = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw JerdError.invalid("Invalid database runtime directory.") }
        for (name, record) in receipt.files {
            let file = directory.appendingPathComponent(name)
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  (info.fileSize ?? Int.max) < 512_000_000 else {
                throw JerdError.invalid("Invalid database runtime file: \(name)")
            }
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            var hash = SHA256()
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == record.sha256 else {
                throw JerdError.invalid("Database runtime verification failed for \(name). The existing file was preserved.")
            }
            if record.executable, !FileManager.default.isExecutableFile(atPath: file.path) {
                throw JerdError.invalid("The database runtime is not executable: \(name)")
            }
        }
    }
}
