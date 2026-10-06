import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdRuntimes
import Testing

/// Opt-in check of the real disk image commands (RT-8): `JERD_DISK_IMAGE=1`. It creates a 2 MB
/// image in a temporary folder, attaches and ejects it with the production arguments, and fails
/// when the eject stops working or prints a deprecation warning on a new macOS.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["JERD_DISK_IMAGE"] == "1"))
struct LiveDiskImageTests {
    private func isMountPoint(_ url: URL) -> Bool {
        var folder = stat()
        var parent = stat()
        guard stat(url.path, &folder) == 0, stat(url.deletingLastPathComponent().path, &parent) == 0 else {
            return false
        }
        return folder.st_dev != parent.st_dev
    }

    @Test func productionEjectDetachesTheImageWithoutAWarning() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let runner = CommandRunner()
        let image = folder.path("test.dmg")
        let mount = folder.path("volume")
        try OwnedDirectory.create(mount)
        let create = ProcessRequest(
            executable: URL(fileURLWithPath: DiskImageMount.hdiutil),
            arguments: ["create", "-size", "2m", "-fs", "HFS+", "-volname", "JerdTest", image.path],
            workingDirectory: folder.url)
        #expect(try await runner.run(create, timeout: .seconds(60)).succeeded)
        let attach = ProcessRequest(
            executable: URL(fileURLWithPath: DiskImageMount.hdiutil),
            arguments: DiskImageMount.attachArguments(image: image, mountPoint: mount), workingDirectory: folder.url)
        #expect(try await runner.run(attach, timeout: .seconds(60)).succeeded)
        #expect(isMountPoint(mount))
        let eject = DiskImageMount.ejectRequest(mountPoint: mount, workingDirectory: folder.url)
        let ejected = try await runner.run(eject, timeout: .seconds(60))
        #expect(ejected.succeeded, "\(ejected.diagnosticOutput)")
        #expect(!ejected.output.lowercased().contains("deprecated"))
        #expect(!isMountPoint(mount))
        let again = try await runner.run(eject, timeout: .seconds(60))
        #expect(!again.succeeded, "An eject of a folder that is not a mount point must fail.")
    }
}
