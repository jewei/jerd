import Foundation

/// What every command needs: the repository, the programs, a process runner, the console, and the
/// environment of `./dev`.
struct DevContext: Sendable {
    let repository: Repository
    let toolchain: Toolchain
    let runner: any ProcessRunning
    let console: Console
    let environment: [String: String]

    /// The live context for the repository that contains the working directory.
    /// - Parameter json: Send every line to standard error, because standard output carries the JSON summary.
    static func live(verbose: Bool, json: Bool = false) throws -> DevContext {
        let output = StandardTextOutput(sendsEverythingToStandardError: json)
        let environment = ProcessInfo.processInfo.environment
        let workingDirectory = URL(filePath: FileManager.default.currentDirectoryPath)
        let located = Repository.locate(from: workingDirectory) { FileManager.default.fileExists(atPath: $0) }
        guard let repository = located else {
            throw DevFailure.usage("Run ./dev inside the Jerd repository.")
        }
        return DevContext(
            repository: repository,
            toolchain: .live(environment: environment),
            runner: ProcessRunner(output: output),
            console: Console(output: output, verbose: verbose),
            environment: environment)
    }

    /// Runs a planned command. In verbose mode the console shows the command line first.
    func run(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult {
        console.command(invocation)
        return try await runner.run(invocation, output: output)
    }

    @discardableResult
    func runChecked(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult {
        try await run(invocation, output: output).checked()
    }
}
