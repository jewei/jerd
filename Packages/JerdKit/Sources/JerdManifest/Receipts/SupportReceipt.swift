import Foundation
import JerdFoundation

/// The record of a built support library: `support-receipt.json` beside the library files.
///
/// `./dev runtimes prepare` writes it in `.build/runtimes/support/<name>/`, and the build copies the
/// folder into the app as `RuntimePayloads/support/<name>/`. The release tool signs the library and
/// records the new digests with a signing record. The app checks every file against it before it
/// gives the library to a preparation (`BundledSupportLibrary`).
public struct SupportReceipt: Codable, Equatable, Sendable {
    public static let fileName = "support-receipt.json"
    public static let currentSchemaVersion = 1
    /// A receipt file must be at most this many bytes.
    public static let sizeLimit = 64 * 1024

    public private(set) var schemaVersion = Self.currentSchemaVersion
    /// The support source name in the pin catalog, for example `xz`.
    public let name: String
    public let version: String
    /// The SHA-256 of the pinned source archive.
    public let archiveSHA256: String
    /// The `MACOSX_DEPLOYMENT_TARGET` of the build, for example `14.0`.
    public let deploymentTarget: String
    /// The SHA-256 of each file in the folder, by file name.
    public let files: [String: String]
    /// Set by the release tool after it signs the library.
    public let signing: PayloadSigning?

    public init(
        name: String, version: String, archiveSHA256: String, deploymentTarget: String, files: [String: String],
        signing: PayloadSigning? = nil
    ) {
        self.name = name
        self.version = version
        self.archiveSHA256 = archiveSHA256
        self.deploymentTarget = deploymentTarget
        self.files = files
        self.signing = signing
    }

    /// True when this receipt records exactly `source`, and, when given, built for `deploymentTarget`.
    public func matches(_ source: PinnedSupportSource, deploymentTarget: String? = nil) -> Bool {
        schemaVersion == Self.currentSchemaVersion && version == source.version
            && archiveSHA256 == source.archive.sha256 && (deploymentTarget.map { $0 == self.deploymentTarget } ?? true)
    }

    /// The same receipt with new file digests, for example after the release tool signs the library.
    public func replacingFiles(_ newFiles: [String: String], signing: PayloadSigning?) -> SupportReceipt {
        SupportReceipt(
            name: name, version: version, archiveSHA256: archiveSHA256, deploymentTarget: deploymentTarget,
            files: newFiles, signing: signing)
    }

    /// The folder holds exactly the recorded files, each a regular file with its digest, plus the
    /// receipt. Finder's `.DS_Store` is not allowed: the folder is copied without it.
    /// - Throws: `.invalid` naming the first difference.
    public func verify(in folder: URL) throws {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != Self.fileName }
        } catch {
            throw JerdError.invalid("Cannot read the \(name) support folder \(folder.path).")
        }
        guard Set(names) == Set(files.keys) else {
            throw JerdError.invalid("The \(name) support folder has other files than its receipt.")
        }
        for (file, digest) in files.sorted(by: { $0.key < $1.key }) {
            let url = folder.appendingPathComponent(file)
            guard FileProbe.presence(at: url) == .present, Self.isRegularFile(url),
                (try? FileDigest.hexSHA256(of: url)) == digest
            else { throw JerdError.invalid("The \(name) support file \(file) changed.") }
        }
    }

    /// The exact bytes to save: pretty, sorted keys, and a final newline.
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// Decodes and validates receipt bytes.
    public static func decode(_ data: Data) throws -> SupportReceipt {
        guard data.count <= sizeLimit else { throw JerdError.invalid("The support receipt is too large.") }
        let receipt: SupportReceipt
        do {
            receipt = try JSONDecoder().decode(SupportReceipt.self, from: data)
        } catch {
            throw JerdError.invalid("The support receipt cannot be read. \(FailureDetail.describe(error))")
        }
        try receipt.validate()
        return receipt
    }

    /// The receipt in `folder`, or nil when the folder has none. The file may be readable by others
    /// (a build folder or an app bundle), but it must be a regular file, not a link.
    public static func read(from folder: URL) throws -> SupportReceipt? {
        let file = folder.appendingPathComponent(fileName)
        guard FileProbe.presence(at: file).mayExist else { return nil }
        guard isRegularFile(file) else { throw JerdError.invalid("The support receipt \(file.path) is invalid.") }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw JerdError.unavailable("Cannot read the support receipt \(file.path).")
        }
        return try decode(data)
    }

    /// Schema 1, a parseable version, valid digests, and 1 to 16 plain file names.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw JerdError.invalid("The support receipt has an unsupported format version.")
        }
        guard !name.isEmpty, RuntimeVersion(version) != nil, FileDigest.isSHA256Hex(archiveSHA256),
            RuntimeVersion(deploymentTarget) != nil
        else { throw JerdError.invalid("The support receipt has an invalid identity.") }
        guard (1...16).contains(files.count),
            files.allSatisfy({ Self.isPlainName($0.key) && FileDigest.isSHA256Hex($0.value) })
        else { throw JerdError.invalid("The support receipt has an invalid file list.") }
        if let signing {
            guard PayloadReceipt.isTeamID(signing.teamID), FileDigest.isSHA256Hex(signing.sourceReceiptSHA256) else {
                throw JerdError.invalid("The support receipt has an invalid signing record.")
            }
        }
    }

    /// One file name in the folder itself: no path separator, not hidden, not the receipt.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && name != fileName
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
    }
}
