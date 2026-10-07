import Foundation

/// Builds the signed, notarized, and stapled disk image: `Jerd.app` and a link to `/Applications`.
struct DiskImageBuilder: Sendable {
    let shell: ReleaseShell
    let signing: SigningIdentity
    let layout: CandidateLayout

    /// LZMA compression: about 28 % smaller than zlib (`UDZO`) for Jerd 0.1.1 (87 MB, not 122 MB).
    /// macOS opens it since 10.15, and Jerd requires macOS 14. It takes about a minute to build.
    static let format = "ULMO"

    /// The `hdiutil create` arguments of the read-only, compressed disk image.
    static func createArguments(folder: URL, image: URL) -> [String] {
        ["create", "-volname", "Jerd", "-srcfolder", folder.path, "-format", format, image.path]
    }

    /// - Returns: the notary submission ID.
    func build(_ image: URL, notarizer: Notarizer) async throws -> String {
        let folder = layout.diskImageFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await shell.run(
            SystemProgram.ditto, [layout.app.path, folder.appending(path: "Jerd.app").path], limit: TimeLimit.appCopy)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "Applications"), withDestinationURL: URL(filePath: "/Applications"))
        try await shell.run(
            SystemProgram.hdiutil, Self.createArguments(folder: folder, image: image), limit: TimeLimit.diskImage,
            log: layout.log("disk-image"))
        // A disk image has no hardened runtime; it gets a timestamped Developer ID signature.
        try await shell.run(
            SystemProgram.codesign, ["--sign", signing.identity, "--timestamp", image.path],
            limit: TimeLimit.codeSigning)
        return try await notarizer.notarize(image, name: "dmg", staple: image)
    }
}
