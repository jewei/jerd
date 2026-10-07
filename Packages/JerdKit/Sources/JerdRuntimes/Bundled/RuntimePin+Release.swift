import Foundation
import JerdFoundation
import JerdManifest

extension RuntimePin {
    /// The release that the pin names: the exact archive URL and size, its SHA-256, and the
    /// reviewed MySQL signature file. `./dev runtimes prepare` and the on-demand installation of
    /// the app both use it, so both install exactly the pinned artifact.
    /// - Parameter catalogDirectory: The folder of the catalog, for the Laravel Composer project.
    ///   Nil where no such folder exists (the app bundle); a Composer pin then throws.
    public func release(architecture: CPUArchitecture, catalogDirectory: URL?) throws -> RuntimeRelease {
        let artifact: ReleaseArtifact
        if let archive {
            artifact = .archive(archive.url, size: .exact(archive.size))
        } else if let project = composerProject, let catalogDirectory {
            artifact = .lockedComposerProject(project.directory.url(in: catalogDirectory))
        } else {
            throw JerdError.invalid("The pin \(id) names no artifact.")
        }
        return RuntimeRelease(
            kind: kind, version: version, artifact: artifact, archiveSHA256: artifactSHA256,
            signatureURL: signature?.url, releasePage: releasePage, architecture: architecture,
            pinnedSignature: signature, engineVersion: engineVersion, installedSize: installedSize)
    }
}
