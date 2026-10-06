import Foundation
import JerdFoundation
import JerdManifest

extension ManagedRuntimeStore {
    /// The installed and verified build of `release`, when one exists.
    ///
    /// With a digest: the current folder name, then the legacy name; a folder of the same name with
    /// another kind or version is an error, with another digest it is skipped. Without a digest
    /// (MySQL, Laravel): any usable build of the kind and version.
    public func existing(_ release: RuntimeRelease) throws -> ManagedRuntime? {
        guard let sha256 = release.archiveSHA256 else { return try existingWithoutDigest(release) }
        let names = [
            BuildReceipt.folderName(
                kind: release.kind, releaseVersion: release.version, architecture: architecture, archiveSHA256: sha256),
            BuildReceipt.legacyFolderName(
                kind: release.kind, releaseVersion: release.version, architecture: architecture),
        ]
        for name in names {
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            guard FileProbe.presence(at: folder).mayExist else { continue }
            let receipt = try receipt(at: folder)
            guard receipt.kind == release.kind, receipt.releaseVersion == release.version else {
                throw JerdError.invalid("The installed runtime has conflicting metadata. It was preserved.")
            }
            guard receipt.archiveSHA256 == sha256 else { continue }
            try verify(receipt, at: folder)
            return try runtime(at: folder)
        }
        return nil
    }

    /// The verified build in the target folder of a prepared payload, when it already exists.
    public func existingBuild(
        kind: RuntimeKind, releaseVersion: String, archiveSHA256: String
    ) throws -> ManagedRuntime? {
        let name = BuildReceipt.folderName(
            kind: kind, releaseVersion: releaseVersion, architecture: architecture, archiveSHA256: archiveSHA256)
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        guard FileProbe.presence(at: folder).mayExist else { return nil }
        let receipt = try receipt(at: folder)
        guard receipt.kind == kind, receipt.releaseVersion == releaseVersion, receipt.archiveSHA256 == archiveSHA256
        else { throw JerdError.invalid("The installed build has conflicting metadata. It was preserved.") }
        try verify(receipt, at: folder)
        return try runtime(at: folder)
    }

    private func existingWithoutDigest(_ release: RuntimeRelease) throws -> ManagedRuntime? {
        for candidate in installed() where candidate.matches(release) {
            let receipt = try receipt(at: candidate.directory)
            try verify(receipt, at: candidate.directory)
            return candidate
        }
        return nil
    }
}
