import Foundation
import JerdFoundation
import JerdManifest

/// The record of a built support library: `.build/runtimes/support/<name>/support-receipt.json`.
///
/// A later `./dev runtimes prepare` reuses the build only when the source pin, the deployment
/// target, and every file digest still match, so XZ is not downloaded and built on every run.
struct SupportReceipt: Codable, Equatable, Sendable {
    static let fileName = "support-receipt.json"
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var name: String
    var version: String
    var archiveSHA256: String
    var deploymentTarget: String
    /// The SHA-256 of each file in the folder, by file name.
    var files: [String: String]

    /// True when this receipt records exactly `source` built for `deploymentTarget`.
    func matches(_ source: PinnedSupportSource, deploymentTarget: String) -> Bool {
        schemaVersion == Self.currentSchemaVersion && version == source.version
            && archiveSHA256 == source.archive.sha256 && self.deploymentTarget == deploymentTarget
    }

    /// Every recorded file exists in `folder` as a regular file with its digest, and no other file exists.
    func verify(in folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter {
            $0 != Self.fileName
        }
        guard Set(names) == Set(files.keys) else {
            throw DevFailure.checkFailed("The \(name) support folder has other files than its receipt.")
        }
        for (file, digest) in files where try FileDigest.hexSHA256(of: folder.appending(path: file)) != digest {
            throw DevFailure.checkFailed("The \(name) support file \(file) changed.")
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    static func read(from folder: URL) throws -> SupportReceipt? {
        let file = folder.appending(path: fileName)
        guard FileProbe.presence(at: file).mayExist else { return nil }
        return try JSONDecoder().decode(SupportReceipt.self, from: Data(contentsOf: file))
    }
}
