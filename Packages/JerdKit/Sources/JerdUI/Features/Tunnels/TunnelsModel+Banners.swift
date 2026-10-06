import Foundation

extension TunnelsModel {
    /// The error banners of a tunnel page, each once and never the operation failure again:
    /// the connector failure, the launch failure, and the stop failure. The first banner that
    /// an edit can fix offers Edit Tunnel…, unless the settings issue banner already does.
    func banners(for id: UUID) -> [TunnelBanner] {
        let candidates: [(String, String?, Bool)] = [
            ("The connector stopped", state(of: id).failureMessage, true),
            ("The tunnel did not connect when Jerd opened", startupFailures[id], true),
            ("The connector did not stop", stopFailures[id], false),
        ]
        var shown: [TunnelBanner] = []
        for case (let title, let message?, let canBeFixedByEdit) in candidates
        where message != operation.failureMessage && !shown.contains(where: { $0.message == message }) {
            let offersEdit =
                canBeFixedByEdit && snapshots[id]?.settingsIssue == nil && !shown.contains(where: \.offersEdit)
            shown.append(TunnelBanner(title: title, message: message, offersEdit: offersEdit))
        }
        return shown
    }

    /// True when a banner of the page carries Edit Tunnel…: a failure that an edit can fix, or
    /// settings that need an edit. The header then does not repeat it.
    func bannerOffersEdit(for id: UUID) -> Bool {
        snapshots[id]?.settingsIssue != nil || banners(for: id).contains(where: \.offersEdit)
    }
}
