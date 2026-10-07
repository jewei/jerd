import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// Compiles each C fixture with `/usr/bin/cc`, through `CommandRunner`, into one stable folder.
///
/// A binary is named by the hash of its source, so test runs reuse it and leave no new folder in
/// `$TMPDIR`. A changed source gets a new name. Parallel runs compile into a
/// private temporary name and rename it into place, so no run sees a partial binary.
actor Fixtures {
    static let shared = Fixtures()

    /// The stable folder. The non-ASCII name keeps every fixture path test also a Unicode path test.
    static let defaultFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("jerd-process-fixtures ü", isDirectory: true)

    private var builds: [String: Task<URL, any Error>] = [:]
    private let folder: URL

    init(folder: URL = Fixtures.defaultFolder) { self.folder = folder }

    /// The compiled executable of `Fixtures/<name>.c`.
    func executable(_ name: String) async throws -> URL {
        if let build = builds[name] { return try await build.value }
        let folder = folder
        let build = Task { try await Self.build(name, in: folder) }
        builds[name] = build
        return try await build.value
    }

    private static func build(_ name: String, in folder: URL) async throws -> URL {
        try OwnedDirectory.create(folder)
        guard let sources = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw JerdError.unavailable("The test fixtures are missing.")
        }
        let source = sources.appendingPathComponent("\(name).c")
        let hash = try FileDigest.hexSHA256(of: source).prefix(16)
        let binary = folder.appendingPathComponent("\(name)-\(hash)")
        if FileManager.default.isExecutableFile(atPath: binary.path) { return binary }
        let temporary = folder.appendingPathComponent(".\(name)-\(UUID().uuidString).tmp")
        defer { unlink(temporary.path) }
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/cc"), arguments: [source.path, "-o", temporary.path],
            workingDirectory: folder)
        let result = try await CommandRunner().run(request, timeout: .seconds(60))
        guard result.succeeded else { throw JerdError.processFailed("Cannot compile \(name): \(result.output)") }
        guard rename(temporary.path, binary.path) == 0 else {
            throw JerdError.unavailable("Cannot keep the fixture \(name) (\(SystemError.describe(errno))).")
        }
        return binary
    }
}
