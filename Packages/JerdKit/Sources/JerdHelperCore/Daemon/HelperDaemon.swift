import Darwin
import Foundation
import JerdSystem

/// The entry point of the privileged helper (`Apps/JerdHelper/main.swift` calls `run()`).
///
/// It never starts a process and never accepts a path, command, executable, or network target over
/// XPC. On any start error it writes `Jerd helper: <message>` to standard error and exits with 1.
public enum HelperDaemon {
    public static func run(arguments: [String] = CommandLine.arguments) -> Never {
        do {
            let plan = try HelperLaunchPlan.decide(
                arguments: arguments, effectiveUserID: geteuid(), teamID: CodeSigningPolicy.currentTeamID)
            switch plan {
            case .printSigning(let message):
                print(message)
                exit(0)
            case .listen(let requirement):
                listen(requirement: requirement)
            }
        } catch {
            FileHandle.standardError.write(Data("Jerd helper: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// Serves the Mach service until launchd stops the process. The listener checks the code-signing
    /// requirement, and the delegate checks it again on every connection.
    private static func listen(requirement: String) -> Never {
        let listener = NSXPCListener(machServiceName: HelperServiceIdentity.machServiceName)
        let delegate = HelperListenerDelegate(requirement: requirement, service: HelperService.live())
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { dispatchMain() }
    }
}
