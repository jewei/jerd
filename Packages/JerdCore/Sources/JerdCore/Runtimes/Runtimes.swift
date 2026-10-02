import Foundation

public struct DevelopmentRuntimeProvider: Sendable {
    private let runner: any CommandRunning
    public init(runner: any CommandRunning = LocalCommandRunner()) { self.runner = runner }

    public func inspectPHP(cli: URL, fpm: URL, workDirectory: URL) async throws -> DevelopmentRuntime {
        try await prepare(workDirectory)
        let (cli, fpm) = try await Task.detached {
            let cli = cli.resolvingSymlinksInPath()
            let fpm = fpm.resolvingSymlinksInPath()
            try self.rejectHerd(cli)
            try self.rejectHerd(fpm)
            return (cli, fpm)
        }.value
        let cliArchitectures = try await architectures(cli, directory: workDirectory)
        let fpmArchitectures = try await architectures(fpm, directory: workDirectory)
        let common = cliArchitectures.filter { fpmArchitectures.contains($0) }
        guard common.contains(.current) else {
            throw JerdError.unavailable("Both PHP executables must contain the current process architecture.")
        }
        // This is app-owned inspection code. No project file is executed.
        let script = "echo json_encode(['version'=>PHP_VERSION,'sapi'=>PHP_SAPI,'extensions'=>get_loaded_extensions()]);"
        let cliResult = try await command(cli, ["-n", "-r", script], workDirectory)
        struct CLIInfo: Decodable { let version: String; let sapi: String; let extensions: [String] }
        let info: CLIInfo
        do { info = try JSONDecoder().decode(CLIInfo.self, from: Data(cliResult.utf8)) }
        catch { throw JerdError.invalid("The selected CLI did not return valid PHP inspection data.") }
        guard info.sapi == "cli" else { throw JerdError.invalid("Select a PHP CLI executable.") }
        let fpmVersionOutput = try await command(fpm, ["-n", "-v"], workDirectory)
        let fields = fpmVersionOutput.split(whereSeparator: \.isWhitespace)
        guard fields.count > 2, fields[0] == "PHP", fields[1] == Substring(info.version),
              fpmVersionOutput.contains("fpm-fcgi") else {
            throw JerdError.invalid("PHP CLI and PHP-FPM must report the same full version and the correct SAPI.")
        }
        let modules = try await command(fpm, ["-n", "-m"], workDirectory)
        let extensions = Self.parseModules(modules)
        guard !extensions.isEmpty else { throw JerdError.invalid("PHP-FPM returned no extension list.") }
        return DevelopmentRuntime(cliPath: cli.path, fpmPath: fpm.path, version: info.version,
                                  architectures: common, cliExtensions: info.extensions.sorted(),
                                  fpmExtensions: extensions)
    }

    public func inspectCaddy(binary: URL, workDirectory: URL) async throws -> CaddyRuntime {
        try await prepare(workDirectory)
        let binary = try await Task.detached {
            let binary = binary.resolvingSymlinksInPath()
            try self.rejectHerd(binary)
            return binary
        }.value
        let arch = try await architectures(binary, directory: workDirectory)
        guard arch.contains(.current) else { throw JerdError.unavailable("Caddy does not contain the current architecture.") }
        let version = try await command(binary, ["version"], workDirectory).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("v2.") else { throw JerdError.invalid("Select a Caddy 2 executable with a release version.") }
        return CaddyRuntime(path: binary.path, version: version, architectures: arch)
    }

    public static func parseModules(_ output: String) -> [String] {
        var inPHPSection = false
        var modules: Set<String> = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "[PHP Modules]" { inPHPSection = true; continue }
            if line.hasPrefix("[") { inPHPSection = false }
            if inPHPSection && !line.isEmpty { modules.insert(line) }
        }
        return modules.sorted()
    }

    private func prepare(_ directory: URL) async throws {
        try await Task.detached {
            try PrivateFiles.directory(directory)
            try PrivateFiles.directory(directory.appendingPathComponent("empty-ini"))
        }.value
    }

    private func rejectHerd(_ url: URL) throws {
        guard !url.pathComponents.contains(where: { $0.lowercased() == "herd" }) else {
            throw JerdError.invalid("Do not select Herd binaries. Use an independent local build.")
        }
    }

    private func architectures(_ executable: URL, directory: URL) async throws -> [CPUArchitecture] {
        let result = try await runner.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/lipo"),
                                                        arguments: ["-archs", executable.path], directory: directory),
                                          timeout: .seconds(10))
        guard result.status == 0 else { throw JerdError.invalid("Cannot inspect Mach-O architecture: \(executable.path). \(result.output)") }
        return Set(result.output.split(whereSeparator: \.isWhitespace)
            .compactMap { CPUArchitecture(rawValue: String($0)) }).sorted { $0.rawValue < $1.rawValue }
    }

    private func command(_ executable: URL, _ arguments: [String], _ directory: URL) async throws -> String {
        let result = try await runner.run(ProcessRequest(executable: executable, arguments: arguments,
                                                        directory: directory,
                                                        environment: ["PHP_INI_SCAN_DIR": directory.appendingPathComponent("empty-ini").path]),
                                          timeout: .seconds(15))
        guard result.status == 0 else { throw JerdError.process("Runtime inspection failed: \(result.output)") }
        return result.output
    }
}
