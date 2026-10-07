import Darwin
import Foundation
import JerdFoundation
import JerdManifest

@testable import JerdDevKit

/// Writes payloads of every pin of the repository catalog in the bundle layout, with small fake
/// Mach-O files, so release steps can read, sign, and check them.
enum PayloadFixture {
    /// The first bytes of a thin 64-bit Mach-O file.
    static let machO: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]

    static func catalogData() throws -> Data {
        try Data(contentsOf: ReleaseFixtures.repositoryRoot.appending(path: "Runtimes/runtimes.json"))
    }

    /// Writes `<root>/runtimes.json` and `<root>/<group>/<id>/` with a receipt for each bundled pin:
    /// every pin for the prepared payloads, or only the embedded pins for the payloads of an app.
    static func write(to root: URL, embeddedOnly: Bool = false) throws {
        let data = try catalogData()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appending(path: RuntimePinCatalog.fileName))
        let inventory = PayloadInventory(root: root, catalog: try RuntimePinCatalog.decode(data))
        let pins = embeddedOnly ? EmbeddedPayloads.pins(inventory) : inventory.pins(in: PayloadGroup.allCases)
        for (pin, group) in pins {
            try writePayload(pin, in: root.appending(path: "\(group.rawValue)/\(pin.id)"))
        }
    }

    static func writePayload(_ pin: RuntimePin, in folder: URL) throws {
        var files: [(path: String, data: Data, executable: Bool)] = [
            ("bin/tool", Data(machO + Array(pin.id.utf8)), true), ("LICENSE", Data("license".utf8), false),
        ]
        if pin.kind == .php {
            files.append(("bin/php-fpm", Data(machO + Array("fpm".utf8)), true))
        }
        var records: [RelativePath: PayloadFileRecord] = [:]
        for file in files {
            let url = folder.appending(path: file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url)
            chmod(url.path, file.executable ? 0o700 : 0o600)
            records[RelativePath(file.path)!] = PayloadFileRecord(
                sha256: FileDigest.hexSHA256(of: file.data), executable: file.executable)
        }
        let receipt = PayloadReceipt(
            id: pin.id, kind: pin.kind, version: pin.version, releaseVersion: pin.version, architecture: .arm64,
            archiveSHA256: pin.artifactSHA256!, executable: RelativePath("bin/tool")!,
            secondaryExecutable: pin.kind == .php ? RelativePath("bin/php-fpm") : nil, files: records)
        try receipt.encoded().write(to: folder.appending(path: PayloadReceipt.fileName))
    }
}
