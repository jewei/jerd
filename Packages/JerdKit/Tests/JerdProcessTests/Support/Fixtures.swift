import Foundation
import JerdFoundation
import JerdProcess

/// Compiles each C fixture once per test run with `/usr/bin/cc`, through `CommandRunner`.
actor Fixtures {
    static let shared = Fixtures()

    private var builds: [String: Task<URL, any Error>] = [:]
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("jerd-fixtures-\(UUID().uuidString) ü", isDirectory: true)

    /// The compiled executable of `Fixtures/<name>.c`.
    func executable(_ name: String) async throws -> URL {
        if let build = builds[name] { return try await build.value }
        let folder = folder
        let build = Task {
            try OwnedDirectory.create(folder)
            guard let sources = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
                throw JerdError.unavailable("The test fixtures are missing.")
            }
            let binary = folder.appendingPathComponent(name)
            let request = ProcessRequest(
                executable: URL(fileURLWithPath: "/usr/bin/cc"),
                arguments: [sources.appendingPathComponent("\(name).c").path, "-o", binary.path],
                workingDirectory: folder)
            let result = try await CommandRunner().run(request, timeout: .seconds(60))
            guard result.succeeded else { throw JerdError.processFailed("Cannot compile \(name): \(result.output)") }
            return binary
        }
        builds[name] = build
        return try await build.value
    }
}
