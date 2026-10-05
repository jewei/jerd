import Foundation
import JerdFoundation
import JerdProcess

/// Mounts a disk image read-only, verifies the signed app on it, and always detaches it (rule I10).
package struct DiskImageMount: Sendable {
    package static let hdiutil = "/usr/bin/hdiutil"
    package static let codesign = "/usr/bin/codesign"
    /// The time limit of the detach that runs after a failure or a cancellation.
    package static let cleanupTimeout: Duration = .seconds(30)

    package let context: PreparationContext

    package init(context: PreparationContext) { self.context = context }

    /// Attaches `image` at `mountPoint`, requires `app` to satisfy `requirement`, runs `body` with the
    /// app URL, and detaches. On any error, also on cancellation, a detach runs that cannot be
    /// cancelled; its own result is ignored and the original error is thrown.
    package func withVerifiedApp<T: Sendable>(
        image: URL, mountPoint: URL, app: String, requirement: CodeRequirement,
        body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        let staging = context.staging
        do {
            try await context.run(
                Self.hdiutil, ["attach", "-readonly", "-nobrowse", "-mountpoint", mountPoint.path, image.path],
                in: staging)
            let appURL = mountPoint.appendingPathComponent(app)
            try await verify(appURL, requirement: requirement)
            let result = try await body(appURL)
            try await context.run(Self.hdiutil, ["detach", mountPoint.path], in: staging)
            return result
        } catch {
            await detachAfterFailure(mountPoint)
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
    private func detachAfterFailure(_ mountPoint: URL) async {
        let commands = context.commands
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: Self.hdiutil), arguments: ["detach", mountPoint.path],
            workingDirectory: context.staging)
        let cleanup = Task.detached { _ = try await commands.run(request, timeout: Self.cleanupTimeout) }
        _ = await cleanup.result
    }
}
