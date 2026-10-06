import Foundation
import JerdFoundation
import JerdWeb

/// The `php`, `composer`, and `laravel` launcher: selects PHP for the working folder and runs it.
///
/// Each invocation reads the current saved configuration, so a change in Jerd applies to the next
/// command. The launcher writes only the CLI INI files and the CLI CA bundle. On success PHP
/// replaces the launcher with `execve`: standard streams, signals, and the exit status belong to PHP.
/// On failure the launcher writes `Jerd: <message>` to standard error and exits with status 1.
///
/// Trust: the launcher does not hash the runtime on each call (that costs a full read of PHP). It
/// checks only that the selected executable is a regular file that the user can run. The shell
/// setup verifies managed runtimes against their receipts; see `ShellSetupInstaller`.
public struct CLILauncher: Sendable {
    /// The exit status when the command cannot start.
    public static let failureStatus: Int32 = 1

    let layout: DataLayout
    let resolver: CLIRuntimeResolver
    let caBundles: any CLICABundlePreparing
    let processImage: any ProcessImageReplacing
    let diagnostics: any DiagnosticWriting

    package init(
        layout: DataLayout, resolver: CLIRuntimeResolver = CLIRuntimeResolver(),
        caBundles: any CLICABundlePreparing = PHPCABundleBuilder(),
        processImage: any ProcessImageReplacing = ProcessImage(),
        diagnostics: any DiagnosticWriting = StandardErrorWriter()
    ) {
        self.layout = layout
        self.resolver = resolver
        self.caBundles = caBundles
        self.processImage = processImage
        self.diagnostics = diagnostics
    }

    /// The launcher of the current user with the live system. The data root is below `$HOME`,
    /// the same folder that the shell PATH block names.
    public static func live() -> CLILauncher {
        CLILauncher(layout: UserHome.dataLayout(home: UserHome.current()))
    }

    /// Runs the command. Returns only when it cannot start, with `failureStatus`.
    public func run(_ invocation: CLIInvocation) -> Int32 {
        do {
            let plan = try prepare(invocation)
            let code = processImage.replace(with: plan)
            throw JerdError.processFailed("Cannot run PHP: \(SystemError.describe(code))")
        } catch {
            diagnostics.writeLine("Jerd: \(FailureDetail.describe(error))")
            return Self.failureStatus
        }
    }

    /// Selects PHP, writes the INI when needed, and returns the plan. It starts nothing.
    func prepare(_ invocation: CLIInvocation) throws -> CLILaunchPlan {
        let names = invocation.decodedArguments
        let command = try CLICommand(invocationName: names.first ?? "")
        guard let workingDirectory = invocation.workingDirectory else {
            throw JerdError.unavailable("Cannot read the current folder. Change to an existing folder and try again.")
        }
        let configuration = try ConfigurationCodec.store(in: layout).load() ?? AppConfiguration()
        let selection = try resolver.resolve(configuration, workingDirectory: workingDirectory)
        let executable = selection.runtime.cliPath
        guard Self.isExecutableFile(executable) else {
            throw JerdError.unavailable(
                "PHP \(selection.runtime.version) selected for \(selection.selectorName) is unavailable: \(executable)")
        }
        let decision = CLIIniDecision(
            command: command, arguments: Array(names.dropFirst()), environment: invocation.environment)
        let writer = CLIIniWriter(layout: layout)
        var iniEnvironment: [String: String] = [:]
        if decision.usesEmptyScanDirectory {
            iniEnvironment[CLIIniDecision.scanDirectoryVariable] = try writer.prepareEmptyScanDirectory().path
        }
        return try CLILaunchPlanner.plan(
            CLILaunchRequest(
                command: command, phpExecutable: executable,
                iniArguments: try iniArguments(for: decision, writer: writer),
                companionScript: try companionScript(for: command),
                userArguments: Array(invocation.arguments.dropFirst()), environment: invocation.environment,
                iniEnvironment: iniEnvironment, binDirectory: layout.binDirectory.path))
    }
}
