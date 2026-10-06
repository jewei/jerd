import JerdDesign
import SwiftUI

/// The recent connector events of one tunnel, with Refresh. The token is redacted.
struct TunnelLogSheet: View {
    let model: TunnelsModel
    let log: TunnelLogModel

    var body: some View {
        SheetScaffold(
            log.title, message: "Recent events. Select Refresh to load new entries.", size: .wide,
            confirmation: SheetConfirmation("Refresh", cancelTitle: "Done", isEnabled: !log.isLoading, identifier: "tunnel-log") {
                Task { await log.load() }
            },
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
}
