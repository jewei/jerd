import Foundation
import JerdFoundation
import JerdWeb

/// The `php`, `composer`, and `laravel` launcher: selects PHP for the working folder and runs it.
///
/// Each invocation reads the current saved configuration, so a change in Jerd applies to the next
/// command. The launcher writes only the CLI INI files and the CLI CA bundle. On success PHP
/// replaces the launcher with `execv`: standard streams, signals, and the exit status belong to PHP.
/// On failure the launcher writes `Jerd: <message>` to standard error and exits with status 1.
public struct CLILauncher: Sendable {
    /// The exit status when the command cannot start.
    public static let failureStatus: Int32 = 1

    let layout: DataLayout
    let resolver: CLIRuntimeResolver
    let caBundles: any CLICABundlePreparing
    let processImage: any ProcessImageReplacing
    let diagnostics: any DiagnosticWriting

    public init(
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

    /// The launcher of the current user with the live system.
    public static func live() -> CLILauncher {
        CLILauncher(layout: .currentUser())
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
    public func prepare(_ invocation: CLIInvocation) throws -> CLILaunchPlan {
        let command = try CLICommand(invocationName: invocation.arguments.first ?? "")
        let userArguments = Array(invocation.arguments.dropFirst())
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
        let decision = CLIIniDecision(command: command, arguments: userArguments, environment: invocation.environment)
        let writer = CLIIniWriter(layout: layout)
        var iniEnvironment: [String: String] = [:]
        if decision.usesEmptyScanDirectory {
            iniEnvironment[CLIIniDecision.scanDirectoryVariable] = try writer.prepareEmptyScanDirectory().path
        }
        return try CLILaunchPlanner.plan(
            CLILaunchRequest(
                command: command, phpExecutable: executable,
                iniArguments: try iniArguments(for: decision, writer: writer),
                companionScript: try companionScript(for: command), userArguments: userArguments,
                environment: invocation.environment, iniEnvironment: iniEnvironment,
                binDirectory: layout.binDirectory.path))
    }
}
