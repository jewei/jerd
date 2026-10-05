import Darwin
import Foundation
import JerdFoundation
import JerdManifest

/// Reads the managed builds in `runtime-updates/`: listing, receipts, verification, and reuse.
///
/// The folder layout and the receipt format are a compatibility contract (§4.1): current folders
/// `<kind>-<releaseVersion>-<arch>-<sha256>` and legacy folders `<kind>-<releaseVersion>-<arch>`.
public struct ManagedRuntimeStore: Sendable {
    public let directory: URL
    public let architecture: CPUArchitecture

    public init(directory: URL, architecture: CPUArchitecture = .current) {
        self.directory = directory
        self.architecture = architecture
    }

    /// Every visible folder with a receipt, in name order. Hidden folders (staging) are skipped.
    /// A folder that cannot be used is listed with its reason; the others stay usable.
    public func list() -> [ManagedRuntimeListing] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") }.sorted().compactMap { name in
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            guard FileProbe.presence(at: folder.appendingPathComponent(BuildReceipt.fileName)) == .present else {
                return nil
            }
            do {
                return .runtime(try runtime(at: folder))
            } catch {
                return .unusable(folder: name, reason: FailureDetail.describe(error))
            }
        }
    }

    /// The usable builds.
    public func installed() -> [ManagedRuntime] { list().compactMap(\.runtime) }

    /// The build in `folder`, after rules I14 and I15. Files are not hashed.
    public func runtime(at folder: URL) throws -> ManagedRuntime {
        let receipt = try receipt(at: folder)
        guard receipt.matchesFolderName(folder.lastPathComponent, architecture: architecture) else {
            throw JerdError.invalid("The installed runtime directory does not match its receipt.")
        }
        return ManagedRuntime(receipt: receipt, directory: folder)
    }

    /// Reads and validates the receipt of a build folder (I14).
    public func receipt(at folder: URL) throws -> BuildReceipt {
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw JerdError.invalid("The runtime directory is invalid.")
        }
        let data = try AtomicFile.read(
            folder.appendingPathComponent(BuildReceipt.fileName), limit: BuildReceipt.sizeLimit)
        return try BuildReceipt.decode(data)
    }

    /// Hashes every file of a build and requires exactly its receipt (I16). A Finder `.DS_Store` is ignored.
    public func verify(_ receipt: BuildReceipt, at folder: URL) throws {
        let actual = try PayloadScanner.scan(folder, ignoring: [BuildReceipt.fileName], ignoresFinderMetadata: true)
        try PayloadComparison.requireHashes(receipt.fileHashes, actual: actual)
    }
}
