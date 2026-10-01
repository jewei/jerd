import Foundation
import CryptoKit

public actor BundledStorageRuntime {
    private struct Pin: Decodable {
        let schemaVersion: Int
        let id: String
        let version: String
        let architecture: String
        let sha256: String
    }
    private struct Receipt: Decodable {
        let schemaVersion: Int
        let archiveSHA256: String
        let files: [String: String]
    }
    public init() {}

    public func install(from source: URL, into directory: URL) throws -> StorageRuntime {
        let pin = try JSONDecoder().decode(Pin.self, from: Data(contentsOf: source.appendingPathComponent("pin.json")))
        guard pin.schemaVersion == 1, pin.architecture == CPUArchitecture.current.rawValue,
              DatabaseConfiguration.safeIdentifier(pin.id), DatabaseConfiguration.safeIdentifier(pin.version) else {
            throw JerdError.unavailable("The RustFS runtime bundle does not support this Mac.")
        }
        let origin = source.appendingPathComponent(pin.id)
        let receiptData = try Data(contentsOf: origin.appendingPathComponent("receipt.json"))
        let receipt = try JSONDecoder().decode(Receipt.self, from: receiptData)
        guard receipt.schemaVersion == 1, receipt.archiveSHA256 == pin.sha256,
              Set(receipt.files.keys) == ["rustfs", "LICENSE"] else {
            throw JerdError.invalid("The RustFS runtime receipt is invalid.")
        }
        try PrivateFiles.directory(directory)
        let target = directory.appendingPathComponent(pin.id)
        if FileManager.default.fileExists(atPath: target.path) {
            try verify(target, receipt: receipt)
        } else {
            try verify(origin, receipt: receipt)
            let stage = directory.appendingPathComponent(".install-\(UUID().uuidString)")
            try PrivateFiles.directory(stage)
            defer { try? FileManager.default.removeItem(at: stage) }
            for name in receipt.files.keys {
                let file = stage.appendingPathComponent(name)
                try FileManager.default.copyItem(at: origin.appendingPathComponent(name), to: file)
                try FileManager.default.setAttributes([.posixPermissions: name == "rustfs" ? 0o700 : 0o600], ofItemAtPath: file.path)
            }
            try PrivateFiles.write(receiptData, to: stage.appendingPathComponent("receipt.json"))
            try verify(stage, receipt: receipt)
            try FileManager.default.moveItem(at: stage, to: target)
        }
        return StorageRuntime(id: pin.id, version: pin.version, path: target.path)
    }

    private func verify(_ directory: URL, receipt: Receipt) throws {
        let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw JerdError.invalid("Invalid RustFS runtime directory.") }
        for (name, expected) in receipt.files {
            let file = directory.appendingPathComponent(name)
            let fileInfo = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard fileInfo.isRegularFile == true, fileInfo.isSymbolicLink != true, (fileInfo.fileSize ?? Int.max) < 320 * 1024 * 1024 else {
                throw JerdError.invalid("Invalid RustFS runtime file: \(name)")
            }
            let actual = try RuntimeDownload.digest(file)
            guard actual == expected else { throw JerdError.invalid("RustFS verification failed for \(name). The file was preserved.") }
        }
        guard FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("rustfs").path) else {
            throw JerdError.invalid("The RustFS runtime is not executable.")
        }
    }
}
