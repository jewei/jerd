import Foundation
import JerdFoundation
import JerdManifest

/// Proves that a selected PHP executable is a Jerd-managed file with its recorded SHA-256.
///
/// The CLI setup uses it before it links `php` into the user's PATH. The executable must be inside
/// `runtimes/<build>/` (bundled payloads: `payload-receipt.json`, or the legacy `jerd-receipt.json`)
/// or `runtime-updates/<build>/` (`update-receipt.json` of kind PHP). Both receipt generations are read.
///
/// Only the PHP CLI passes (spec B 3.19 step 2, RT-5): the file that the receipt names as its
/// `executable`. A legacy development receipt names no executable; there the CLI is the top-level
/// `php-native-<major>.<minor>` file that the old bootstrap used. FPM and notice files never pass.
public struct ManagedExecutableVerifier: Sendable {
    private let layout: RuntimeLayout

    public init(layout: DataLayout) { self.layout = layout.runtimes }

    /// The verified build folder and the path of the executable inside it.
    public struct Verified: Equatable, Sendable {
        public let build: URL
        public let relativePath: String
    }

    /// - Throws: `.invalid` with a message that says what to do.
    public func verifyPHP(_ executable: URL) throws -> Verified {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL
        guard FileProbe.presence(at: resolved) == .present else { throw Self.notManaged }
        let roots = [(layout.developmentRuntimesDirectory, false), (layout.managedRuntimesDirectory, true)]
        for (root, managed) in roots {
            let base = root.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathComponents.starts(with: base.pathComponents) else { continue }
            let parts = Array(resolved.pathComponents.dropFirst(base.pathComponents.count))
            guard parts.count >= 2, let entry = RelativePath(parts.dropFirst().joined(separator: "/")) else {
                throw Self.notManaged
            }
            let build = base.appendingPathComponent(parts[0], isDirectory: true)
            let expected = try recordedHash(of: entry, in: build, managed: managed)
            guard try FileDigest.hexSHA256(of: resolved) == expected else {
                throw JerdError.invalid("The installed PHP executable failed verification.")
            }
            return Verified(build: build, relativePath: entry.string)
        }
        throw Self.notManaged
    }

    private func recordedHash(of entry: RelativePath, in build: URL, managed: Bool) throws -> String {
        if managed {
            let receipt = try ManagedRuntimeStore(directory: build.deletingLastPathComponent()).receipt(at: build)
            guard receipt.kind == .php, receipt.executable == entry.string, let hash = receipt.files[entry.string]
            else { throw Self.mismatch }
            return hash
        }
        let current = build.appendingPathComponent(PayloadReceipt.fileName)
        if FileProbe.presence(at: current) == .present {
            let receipt = try PayloadReceipt.decode(AtomicFile.read(current, limit: PayloadReceipt.sizeLimit))
            guard receipt.kind == .php, receipt.executable == entry, let record = receipt.files[entry.string]
            else { throw Self.mismatch }
            return record.sha256
        }
        guard Self.isLegacyCLIName(entry) else { throw Self.mismatch }
        let legacy = build.appendingPathComponent(LegacyPayloadReceipt.Format.development.fileName)
        let data = try AtomicFile.read(legacy, limit: LegacyPayloadReceipt.sizeLimit)
        let receipt: LegacyPayloadReceipt
        do {
            receipt = try LegacyPayloadReceipt.decode(data, format: .development)
        } catch {
            throw JerdError.invalid("The installed PHP receipt is not supported.")
        }
        guard let hash = receipt.fileHashes[entry] else { throw Self.mismatch }
        return hash
    }

    /// True for `php-native-<major>.<minor>` at the top of a build, the CLI name of every legacy PHP payload.
    static func isLegacyCLIName(_ entry: RelativePath) -> Bool {
        guard entry.components.count == 1, entry.string.hasPrefix(legacyCLIPrefix) else { return false }
        let parts = entry.string.dropFirst(legacyCLIPrefix.count).split(
            separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    private static let legacyCLIPrefix = "php-native-"

    static var notManaged: JerdError {
        .invalid("Select a managed Jerd PHP runtime before setting up its CLI command.")
    }

    static var mismatch: JerdError {
        .invalid("The installed PHP receipt does not match the selected executable.")
    }
}
