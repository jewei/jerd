import Foundation
import JerdFoundation
import JerdProcess

/// The shared steps of runtime inspection: the work folder, path checks, `lipo`, and one command.
///
/// Inspection runs only the selected executables with fixed app-owned arguments. It never runs
/// project code, and every PHP command uses `-n` and an empty scan folder, so no user INI applies.
struct InspectionCommands: Sendable {
    /// The timeout of `lipo`.
    static let architectureTimeout: Duration = .seconds(10)
    /// The timeout of each runtime command.
    static let commandTimeout: Duration = .seconds(15)

    let commands: any CommandRunning
    let workDirectory: URL

    var emptyINIDirectory: URL { workDirectory.appendingPathComponent("empty-ini", isDirectory: true) }

    /// Creates the private work folder and its empty INI scan folder.
    func prepare() throws {
        try OwnedDirectory.create(workDirectory)
        try OwnedDirectory.create(emptyINIDirectory)
    }

    /// Resolves links and refuses Herd binaries, which belong to another app.
    static func resolve(_ executable: URL) throws -> URL {
        let resolved = executable.resolvingSymlinksInPath()
        guard !resolved.pathComponents.contains(where: { ["herd", "herd.app"].contains($0.lowercased()) }) else {
            throw JerdError.invalid("Do not select Herd binaries. Use an independent local build.")
        }
        return resolved
    }

    /// The known Mach-O architectures of `executable`, unique and sorted.
    func architectures(_ executable: URL) async throws -> [CPUArchitecture] {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/lipo"), arguments: ["-archs", executable.path],
            workingDirectory: workDirectory)
        let result = try await commands.run(request, timeout: Self.architectureTimeout)
        guard result.succeeded else {
            throw JerdError.invalid(
                "Cannot inspect Mach-O architecture: \(executable.path). \(result.diagnosticOutput)")
        }
        let found = Set(
            result.output.split(whereSeparator: \.isWhitespace).compactMap {
                CPUArchitecture(rawValue: String($0))
            })
        return found.sorted { $0.rawValue < $1.rawValue }
    }

    /// The output of one successful command.
    func output(_ executable: URL, _ arguments: [String]) async throws -> String {
        let request = ProcessRequest(
            executable: executable, arguments: arguments, workingDirectory: workDirectory,
            environment: ["PHP_INI_SCAN_DIR": emptyINIDirectory.path])
        let result = try await commands.run(request, timeout: Self.commandTimeout)
        guard result.succeeded else {
            throw JerdError.processFailed("Runtime inspection failed: \(result.diagnosticOutput)")
        }
        return result.output
    }
}
