import Foundation
import JerdFoundation
import JerdProcess

/// Mounts a disk image read-only, verifies the signed app on it, and always ejects it (rule I10).
///
/// The eject uses `diskutil eject <mount point>` (RT-8). macOS 27 prints a deprecation warning for
/// `hdiutil detach` and names this form as its replacement; `diskutil eject` exists on every
/// supported macOS (14 and later). For a path that is not a mount point it fails and ejects nothing.
/// `hdiutil attach` stays: macOS 27 also marks it deprecated, but its replacement
/// `diskutil image attach` and its options are not documented for macOS 14, the oldest supported
/// version. The warning of the attach goes to the command log only; the exit status decides.
package struct DiskImageMount: Sendable {
    package static let hdiutil = "/usr/bin/hdiutil"
    package static let diskutil = "/usr/sbin/diskutil"
    package static let codesign = "/usr/bin/codesign"
    /// The time limit of the eject that runs after a failure or a cancellation.
    package static let cleanupTimeout: Duration = .seconds(30)

    package let context: PreparationContext

    package init(context: PreparationContext) { self.context = context }

    /// The read-only, hidden attach of `image` at `mountPoint`.
    package static func attachArguments(image: URL, mountPoint: URL) -> [String] {
        ["attach", "-readonly", "-nobrowse", "-mountpoint", mountPoint.path, image.path]
    }

    /// The eject of the image that is mounted at `mountPoint`.
    package static func ejectRequest(mountPoint: URL, workingDirectory: URL) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: diskutil), arguments: ["eject", mountPoint.path],
            workingDirectory: workingDirectory)
    }

    /// Attaches `image` at `mountPoint`, requires `app` to satisfy `requirement`, runs `body` with the
    /// app URL, and ejects. On any error, also on cancellation, an eject runs that cannot be
    /// cancelled; its own result is ignored and the original error is thrown.
    package func withVerifiedApp<T: Sendable>(
        image: URL, mountPoint: URL, app: String, requirement: CodeRequirement,
        body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        let staging = context.staging
        do {
            try await context.run(Self.hdiutil, Self.attachArguments(image: image, mountPoint: mountPoint), in: staging)
            let appURL = mountPoint.appendingPathComponent(app)
            try await verify(appURL, requirement: requirement)
            let result = try await body(appURL)
            try await context.run(Self.diskutil, ["eject", mountPoint.path], in: staging)
            return result
        } catch {
            await ejectAfterFailure(mountPoint)
            throw error
        }
    }

    private func verify(_ app: URL, requirement: CodeRequirement) async throws {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: Self.codesign), arguments: requirement.verifyArguments(for: app.path),
            workingDirectory: context.staging)
        let result = try await context.commands.run(request, timeout: .seconds(60))
        guard result.succeeded else {
            throw JerdError.invalid(
                "\(requirement.publisher) does not have the expected publisher signature. "
                    + "\(result.diagnosticOutput.suffix(1_000))")
        }
    }

    /// A detached task does not inherit the cancellation of the failed installation.
    private func ejectAfterFailure(_ mountPoint: URL) async {
        let commands = context.commands
        let request = Self.ejectRequest(mountPoint: mountPoint, workingDirectory: context.staging)
        let cleanup = Task.detached { _ = try await commands.run(request, timeout: Self.cleanupTimeout) }
        _ = await cleanup.result
    }
}
