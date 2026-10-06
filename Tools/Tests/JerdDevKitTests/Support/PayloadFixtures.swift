import Darwin
import Foundation
import JerdFoundation
import JerdManifest

@testable import JerdDevKit

/// Writes payload folders with valid receipts for the pins of the committed catalog, as
/// `./dev runtimes prepare` would, but with small fake files.
enum PayloadFixtures {
    static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The committed `Runtimes/runtimes.json`.
    static func catalog() throws -> RuntimePinCatalog {
        try PayloadInventory.catalog(at: repositoryRoot.appending(path: "Runtimes/runtimes.json"))
    }

    static func pin(_ kind: RuntimeKind) throws -> RuntimePin {
        guard let pin = try catalog().pin(for: kind) else { throw DevFailure.checkFailed("No \(kind) pin.") }
        return pin
    }

    /// A temporary repository with the committed catalog in `Runtimes/` and `Configuration/Base.xcconfig`.
    static func repository() throws -> Repository {
        let root = try TestFixtures.temporaryFolder()
        let catalog = try Data(contentsOf: repositoryRoot.appending(path: "Runtimes/runtimes.json"))
        try TestFixtures.write(String(decoding: catalog, as: UTF8.self), to: "Runtimes/runtimes.json", in: root)
        try TestFixtures.write("MACOSX_DEPLOYMENT_TARGET = 14.0\n", to: "Configuration/Base.xcconfig", in: root)
        return Repository(root: root)
    }

    /// Writes `<root>/<group>/<pin ID>` with an executable, a second executable for PHP, and a license.
    @discardableResult
    static func writePayload(_ kind: RuntimeKind, in root: URL, version: String = "1.0.0") throws -> URL {
        let pin = try pin(kind)
        let folder = root.appending(path: pin.group?.rawValue ?? "none").appending(path: pin.id)
        var files: [String: (text: String, executable: Bool)] = ["bin/\(kind.rawValue)": ("binary", true)]
        files["LICENSE"] = ("license", false)
        if kind == .php { files["sbin/php-fpm"] = ("fpm", true) }
        var records: [RelativePath: PayloadFileRecord] = [:]
        for (path, file) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.text.utf8).write(to: url)
            chmod(url.path, file.executable ? 0o700 : 0o600)
            records[try relative(path)] = PayloadFileRecord(
                sha256: FileDigest.hexSHA256(of: Data(file.text.utf8)), executable: file.executable)
        }
        let receipt = PayloadReceipt(
            id: pin.id, kind: kind, version: version, releaseVersion: pin.version, architecture: .arm64,
            archiveSHA256: pin.artifactSHA256 ?? "", executable: try relative("bin/\(kind.rawValue)"),
            secondaryExecutable: kind == .php ? try relative("sbin/php-fpm") : nil, files: records)
        try receipt.encoded().write(to: folder.appending(path: PayloadReceipt.fileName))
        return folder
    }

    /// Writes a payload for every bundled pin of `groups`.
    static func writePayloads(_ groups: [PayloadGroup] = PayloadGroup.allCases, in root: URL) throws {
        for group in groups {
            for kind in group.kinds where try catalog().pin(for: kind) != nil {
                try writePayload(kind, in: root)
            }
        }
    }

    static func relative(_ text: String) throws -> RelativePath {
        guard let path = RelativePath(text) else { throw DevFailure.checkFailed("Bad path \(text).") }
        return path
    }
}
