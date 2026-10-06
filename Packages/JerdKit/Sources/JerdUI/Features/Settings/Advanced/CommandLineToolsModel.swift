import Observation

/// Dashboard › Advanced › Command-Line Tools: the install status, the install after a
/// confirmation, and its report. It changes the user's shell files, so it always asks first.
@MainActor
@Observable
public final class CommandLineToolsModel {
    public internal(set) var status: CommandLineToolsStatus?
    /// The lines of the last successful installation. They stay for the session, because they
    /// name the shell backup folder and the command that loads the PATH change.
    public internal(set) var report: [String] = []
    public internal(set) var operation: OperationState = .idle
    public var isConfirming = false

    @ObservationIgnored let port: any CommandLineToolsPort

    public init(port: any CommandLineToolsPort) {
        self.port = port
    }

    public func load() async {
        status = await port.status()
    }

    public var canInstall: Bool { status != nil && !operation.isWorking }

    /// The button title for the current status.
    public var actionTitle: String {
        switch status {
        case .installed: "Reinstall Command-Line Tools…"
        case .outdatedLauncher: "Update Command-Line Tools…"
        case .notInstalled, nil: "Install Command-Line Tools…"
        }
    }

    /// The row detail for the current status. The row title already names the commands.
    public var statusDescription: String {
        switch status {
        case .installed: "Installed for zsh."
        case .outdatedLauncher: "An older Jerd installed them. Update to use the launcher of this version."
        case .notInstalled: "Not installed. Terminal commands use the PHP on your PATH."
        case nil: "Checking…"
        }
    }

    public func requestInstall() {
        guard canInstall else { return }
        isConfirming = true
    }

    /// Runs the confirmed installation and shows its report.
    @discardableResult
    public func install() -> Task<Void, Never>? {
        isConfirming = false
        guard canInstall else { return nil }
        operation = .working("Installing the command-line tools…")
        report = []
        return Task {
            do {
                report = try await port.install()
                operation = .idle
            } catch {
                operation = .failed(message: ErrorText.message(for: error))
            }
            status = await port.status()
        }
    }
}
