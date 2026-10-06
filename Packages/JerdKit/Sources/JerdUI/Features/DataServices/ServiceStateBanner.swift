import JerdDesign
import JerdServiceKit
import SwiftUI

/// The banner of a service that failed or did not stop. It explains the state once, at the top
/// of the page; the header badge only names it. A failure shows one short cause line, Open Log,
/// and the last log lines behind a disclosure (`ServiceFailureSummary`).
struct ServiceStateBanner: View {
    let state: ServiceState
    /// The service in a sentence, for example "MySQL service" or "Mail".
    let subject: String
    /// The title of the Stop button, for example "Stop Mail".
    let stopTitle: String
    let identifier: String
    /// The data folder and the log of the service, if Jerd knows them yet.
    var files: ServiceFiles?
    /// Opens the server log. The banner offers it when the log exists.
    var openLog: (@MainActor () -> Void)?

    var body: some View {
        switch state {
        case .failed(let reason):
            let summary = ServiceFailureSummary(
                reason: reason, dataFolder: files?.dataFolder,
                homeFolder: FileManager.default.homeDirectoryForCurrentUser)
            InlineMessage(
                summary.cause, kind: .error, title: "\(subject) failed", style: .banner,
                action: openLogAction, identifier: "\(identifier).failed",
                details: InlineMessageDetails(title: "Last log lines", lines: summary.logLines))
        case .stuck(let pid, let reason):
            InlineMessage(
                Self.stuckMessage(reason: reason, pid: pid, stopTitle: stopTitle), kind: .warning,
                title: "\(subject) did not stop safely", style: .banner, identifier: "\(identifier).stuck")
        case .stopped, .starting, .running, .stopping:
            EmptyView()
        }
    }

    var openLogAction: PageAction? {
        guard let openLog, files?.hasLog == true else { return nil }
        return PageAction("Open Log", identifier: "\(identifier).open-log", perform: openLog)
    }

    /// What `stuck` means and what the user can do. Jerd never force-kills a data service, and
    /// `ShutdownCoordinator` cancels Quit when the stop times out again.
    nonisolated static func stuckMessage(reason: String, pid: Int32, stopTitle: String) -> String {
        "\(reason) Jerd keeps process \(pid), its run record, and its data lock, so nothing else can change the data. "
            + "Select \(stopTitle) to try again. Quit also tries to stop it; if it still does not stop, Jerd stays open."
    }
}
