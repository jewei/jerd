import Foundation

/// Builds the signed, notarized, and stapled disk image: `Jerd.app` and a link to `/Applications`.
struct DiskImageBuilder: Sendable {
    let shell: ReleaseShell
    let signing: SigningIdentity
    let layout: CandidateLayout

    /// - Returns: the notary submission ID.
    func build(_ image: URL, notarizer: Notarizer) async throws -> String {
        let folder = layout.diskImageFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await shell.run(
            SystemProgram.ditto, [layout.app.path, folder.appending(path: "Jerd.app").path], limit: TimeLimit.appCopy)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "Applications"), withDestinationURL: URL(filePath: "/Applications"))
        try await shell.run(
            SystemProgram.hdiutil,
            ["create", "-volname", "Jerd", "-srcfolder", folder.path, "-format", "UDZO", image.path],
            limit: TimeLimit.diskImage, log: layout.log("disk-image"))
        // A disk image has no hardened runtime; it gets a timestamped Developer ID signature.
        try await shell.run(
            SystemProgram.codesign, ["--sign", signing.identity, "--timestamp", image.path],
            limit: TimeLimit.codeSigning)
        return try await notarizer.notarize(image, name: "dmg", staple: image)
    }
}
