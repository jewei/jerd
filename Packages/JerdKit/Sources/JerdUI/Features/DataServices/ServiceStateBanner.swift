import JerdDesign
import JerdServiceKit
import SwiftUI

/// The banner of a service that failed or did not stop. It explains the state once, at the top
/// of the page; the header badge only names it.
struct ServiceStateBanner: View {
    let state: ServiceState
    /// The service in a sentence, for example "MySQL service" or "Mail".
    let subject: String
    /// The title of the Stop button, for example "Stop Mail".
    let stopTitle: String
    let identifier: String

    var body: some View {
        switch state {
        case .failed(let reason):
            InlineMessage(
                reason, kind: .error, title: "\(subject) failed", style: .banner, identifier: "\(identifier).failed")
        case .stuck(let pid, let reason):
            InlineMessage(
                Self.stuckMessage(reason: reason, pid: pid, stopTitle: stopTitle), kind: .warning,
                title: "\(subject) did not stop safely", style: .banner, identifier: "\(identifier).stuck")
        case .stopped, .starting, .running, .stopping:
            EmptyView()
        }
    }

    /// What `stuck` means and what the user can do. Jerd never force-kills a data service, and
    /// `ShutdownCoordinator` cancels Quit when the stop times out again.
    nonisolated static func stuckMessage(reason: String, pid: Int32, stopTitle: String) -> String {
        "\(reason) Jerd keeps process \(pid), its run record, and its data lock, so nothing else can change the data. "
            + "Select \(stopTitle) to try again. Quit also tries to stop it; if it still does not stop, Jerd stays open."
    }
}
