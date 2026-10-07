import JerdDesign
import JerdServiceKit

extension ServiceState {
    /// The status that the page, the sidebar, the dashboard card, and the menu show.
    ///
    /// `stuck` has its own label and the attention tone: the stop did not finish, so Jerd still
    /// owns the process and its data lock, and the user must act.
    public var displayStatus: DisplayStatus {
        switch self {
        case .stopped: DisplayStatus("Stopped", tone: .idle)
        case .starting: DisplayStatus("Starting…", tone: .busy)
        case .running: DisplayStatus("Ready", tone: .ready)
        case .stopping: DisplayStatus("Stopping…", tone: .busy)
        case .failed: DisplayStatus("Failed", tone: .failed)
        case .stuck: DisplayStatus("Did not stop", tone: .attention)
        }
    }

    /// True when the service passed its checks and serves requests.
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// True when the service needs the user: it failed, or it did not stop.
    public var needsAttention: Bool {
        switch self {
        case .failed, .stuck: true
        case .stopped, .starting, .running, .stopping: false
        }
    }

    /// The next lifecycle step: Stop while Jerd owns a process (also to retry a stop that did
    /// not finish), else Start.
    public var offersStop: Bool { processID != nil }
}
