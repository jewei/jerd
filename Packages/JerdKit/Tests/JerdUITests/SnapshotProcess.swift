import Foundation
import Testing

/// Runs the built `jerd-snapshots` in its own process. Page renderings in the test process
/// held the main actor in slices of about 0.25 s for over a minute, so other main-actor suites
/// waited up to 30 s; a child process keeps the test process free.
enum SnapshotProcess {
    /// Runs the built executable and waits without blocking a thread. Its output goes to files,
    /// so a long log can never fill a pipe and stop the child.
    static func run(
        _ arguments: [String]
    ) async throws -> (
        status: Int32, output: String, errors: String
    ) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jerd-page-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appending(path: "output.txt")
        let errorsURL = folder.appending(path: "errors.txt")
        FileManager.default.createFile(atPath: outputURL.path(percentEncoded: false), contents: nil)
        FileManager.default.createFile(atPath: errorsURL.path(percentEncoded: false), contents: nil)
        let process = Process()
        process.executableURL = try executable()
        process.arguments = arguments
        process.standardOutput = try FileHandle(forWritingTo: outputURL)
        process.standardError = try FileHandle(forWritingTo: errorsURL)
        let status = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int32, any Error>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let output = try String(contentsOf: outputURL, encoding: .utf8)
        let errors = try String(contentsOf: errorsURL, encoding: .utf8)
        return (status, output, errors)
    }

    static func executable() throws -> URL {
        let url = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent().appending(path: "jerd-snapshots")
        try #require(
            FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)),
            "Build jerd-snapshots first: swift build --product jerd-snapshots")
        return url
    }
}

/// Finds the test bundle, whose folder also holds the built executables.
private final class BundleMarker {}
