import Darwin
import Foundation
import JerdFoundation
import JerdRuntimes
import JerdWeb

extension CLILauncher {
    /// `["-c", <INI path>]` for Jerd's INI, or empty when the user chose the INI.
    func iniArguments(for decision: CLIIniDecision, writer: CLIIniWriter) throws -> [String] {
        switch decision.choice {
        case .userINI:
            return []
        case .jerdINIWithUserTrust:
            return ["-c", try writer.writeINI(caBundle: nil).path]
        case .jerdINIWithLocalCA:
            return ["-c", try writer.writeINI(caBundle: localCABundle()).path]
        }
    }

    /// The local CA bundle, or nil. A CA problem never stops PHP: the command runs without the
    /// local CA and the launcher writes one warning.
    func localCABundle() -> URL? {
        do {
            guard let bundle = try caBundles.prepareForCLI(layout: layout) else { return nil }
            _ = try PHPIniPolicy.trustSection(caBundle: bundle)
            return bundle
        } catch {
            diagnostics.writeLine(
                "Jerd: warning: PHP runs without the local HTTPS CA. \(FailureDetail.describe(error))")
            return nil
        }
    }

    /// The Composer or Laravel installer script of `command`, or nil for `php`.
    func companionScript(for command: CLICommand) throws -> String? {
        guard command.runsCompanionScript else { return nil }
        let unavailable = JerdError.unavailable(
            "The Jerd \(command.rawValue) tool is unavailable. Open Jerd to install its bundled tools.")
        guard let companions = try CLICompanionStore(layout: layout).load() else { throw unavailable }
        let script = command == .composer ? companions.composerPath : companions.laravelPath
        guard Self.isRegularFile(script), access(script, R_OK) == 0 else { throw unavailable }
        return script
    }

    /// True for a regular file (after links) that the user can run.
    static func isExecutableFile(_ path: String) -> Bool {
        isRegularFile(path) && access(path, X_OK) == 0
    }

    private static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
    }
}
