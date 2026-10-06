import Foundation

/// Checks the disk image itself and the app inside it, which is what users install.
///
/// The image is attached read-only. A failed check never hides behind a failed detach: the check
/// error is reported, and a detach that fails is tried again with `-force`.
struct DiskImageInspection: Sendable {
    let shell: ReleaseShell
    let team: String

    func verify(_ image: URL, exportedApp: URL) async throws {
        try await shell.run(
            SystemProgram.codesign,
            ["--verify", "--strict", "-R", SigningIdentity.requirement(team: team), image.path],
            limit: TimeLimit.codeSigning)
        try await shell.xcrun(["stapler", "validate", image.path], limit: TimeLimit.assessment)
        try await shell.run(
            SystemProgram.spctl, ["--assess", "--type", "open", "--context", "context:primary-signature", image.path],
            limit: TimeLimit.assessment)
        try await shell.run(SystemProgram.hdiutil, ["verify", image.path], limit: TimeLimit.diskImage)
        let mount = try FileTree.makeTemporaryFolder(prefix: "jerd-release-mount")
        defer { try? FileManager.default.removeItem(at: mount) }
        try await shell.run(
            SystemProgram.hdiutil, ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, image.path],
            limit: TimeLimit.diskImage)
        var failure: (any Error)?
        do {
            try await checkMountedApp(mount.appending(path: "Jerd.app"), exportedApp: exportedApp)
        } catch {
            failure = error
        }
        let detached = await detach(mount)
        if let failure {
            if !detached { shell.console.warning("Could not detach \(mount.path). Detach it in Finder.") }
            throw failure
        }
        guard detached else { throw DevFailure.checkFailed("Could not detach the disk image at \(mount.path).") }
    }

    func checkMountedApp(_ app: URL, exportedApp: URL) async throws {
        try await shell.run(
            SystemProgram.codesign, ["--verify", "--deep", "--strict", app.path], limit: TimeLimit.codeSigning)
        try await shell.xcrun(["stapler", "validate", app.path], limit: TimeLimit.assessment)
        try await shell.run(
            SystemProgram.spctl, ["--assess", "--type", "execute", app.path], limit: TimeLimit.assessment)
        for path in ["Contents/Info.plist", "Contents/MacOS/Jerd", "Contents/_CodeSignature/CodeResources"] {
            let mounted = try Data(contentsOf: app.appending(path: path))
            let exported = try Data(contentsOf: exportedApp.appending(path: path))
            guard mounted == exported else {
                throw DevFailure.checkFailed("The disk image contains another app: \(path) differs.")
            }
        }
    }

    /// True when the image is detached, with `-force` as the second try.
    func detach(_ mount: URL) async -> Bool {
        for arguments in [["detach", mount.path], ["detach", "-force", mount.path]] {
            let result = try? await shell.result(SystemProgram.hdiutil, arguments, limit: TimeLimit.diskImage)
            if result?.succeeded == true { return true }
        }
        return false
    }
}
