import Observation

/// Dashboard › Advanced › Command-Line Tools: the install state, the install after a
/// confirmation, and its report. It changes the user's shell files, so it always asks first.
@MainActor
@Observable
public final class CommandLineToolsModel {
    public internal(set) var state: CommandLineToolsState?
    /// The lines of the last successful installation.
    public internal(set) var report: [String] = []
    public internal(set) var operation: OperationState = .idle
    public var isConfirming = false

    @ObservationIgnored let port: any CommandLineToolsPort

    public init(port: any CommandLineToolsPort) {
        self.port = port
    }

    public func load() async {
        state = await port.state()
    }

    public var canInstall: Bool { state != nil && !operation.isWorking }

    /// The button title for the current state.
    public var actionTitle: String {
        switch state {
        case .installed: "Reinstall Command-Line Tools…"
        case .outdated: "Update Command-Line Tools…"
        case .notInstalled, nil: "Install Command-Line Tools…"
        }
    }

    /// The row detail for the current state.
    public var stateDescription: String {
        switch state {
        case .installed: "Installed. php, composer, and laravel use the PHP of the current site."
        case .outdated: "An older version is installed. Update it to use the current launcher."
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
            state = await port.state()
        }
    }
}
