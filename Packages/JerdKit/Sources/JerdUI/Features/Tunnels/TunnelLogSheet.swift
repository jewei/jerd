import JerdDesign
import SwiftUI

/// The recent connector events of one tunnel, with Refresh. The token is redacted.
struct TunnelLogSheet: View {
    let model: TunnelsModel
    let log: TunnelLogModel

    var body: some View {
        SheetScaffold(
            log.title, message: log.subtitle, size: .wide,
            confirmation: Self.confirmation(model: model, log: log),
            workingMessage: log.isLoading ? "Loading the log…" : nil, cancel: { model.sheet = nil }
        ) {
            if let failure = log.failure {
                InlineMessage(failure, kind: .error, identifier: "tunnel-log.error")
            }
            Section {
                Text(log.text.isEmpty ? "No connector events yet." : log.text)
                    .font(TextRole.code.font)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Connector log")
            }
        }
        .task { await log.load() }
    }

    /// The log is information, so Done is the one default button on the far right. Refresh
    /// reads the log again inside the sheet, so it is the secondary button on the leading side.
    static func confirmation(model: TunnelsModel, log: TunnelLogModel) -> SheetConfirmation {
        .done(
            secondary: SheetSecondaryAction("Refresh", isEnabled: !log.isLoading) { Task { await log.load() } },
            identifier: "tunnel-log"
        ) { model.sheet = nil }
    }
}
