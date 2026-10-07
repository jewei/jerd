import Darwin
import Foundation

@testable import JerdCLICore

extension CLIInvocation {
    /// An invocation from text arguments and variables (always valid UTF-8).
    init(arguments: [String], environment: [String: String], workingDirectory: String?) {
        self.init(
            arguments: arguments.map { Array($0.utf8) }, environment: CLIEnvironment(environment),
            workingDirectory: workingDirectory)
    }
}

extension CLILaunchPlan {
    /// The argument vector decoded as UTF-8, for expectations on valid text.
    var argumentText: [String] { arguments.map { String(decoding: $0, as: UTF8.self) } }
}

/// The output and exit status of a plan that ran in a child process.
struct SpawnResult {
    let output: Data
    let status: Int32
}

/// Runs `plan` in a child with `posix_spawn`, with the exact vectors that the launcher gives
/// `execve`, and collects its standard output.
func spawn(_ plan: CLILaunchPlan) throws -> SpawnResult {
    var pipeEnds: [Int32] = [0, 0]
    guard pipe(&pipeEnds) == 0 else { throw POSIXError(.EIO) }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, pipeEnds[1], STDOUT_FILENO)
    posix_spawn_file_actions_addclose(&actions, pipeEnds[0])
    var child: pid_t = 0
    let code = ProcessImage.withVectors(of: plan) { path, arguments, environment in
        posix_spawn(&child, path, &actions, nil, arguments, environment)
    }
    close(pipeEnds[1])
    let reader = FileHandle(fileDescriptor: pipeEnds[0], closeOnDealloc: true)
    guard code == 0 else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    let output = reader.readDataToEndOfFile()
    var status: Int32 = 0
    waitpid(child, &status, 0)
    return SpawnResult(output: output, status: (status >> 8) & 0xFF)
}
