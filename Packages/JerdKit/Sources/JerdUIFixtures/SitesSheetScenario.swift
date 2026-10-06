import Foundation
import JerdUI

/// A named state of one Sites or tunnel sheet, for snapshots. The offscreen window cannot show
/// a sheet, so each sheet renders alone at its own width and at most its maximum height: the
/// image shows what the user sees without scrolling.
public enum SitesSheetScenario: String, CaseIterable, Sendable {
    case siteEditorAdd = "sheet-site-editor-add"
    case siteEditorEdit = "sheet-site-editor-edit"
    case siteEditorFailure = "sheet-site-editor-failure"
    case httpsApproval = "sheet-https-approval"
    case httpsApprovalRunning = "sheet-https-approval-running"
    case httpsApprovalFailure = "sheet-https-approval-failure"
    case tunnelEditorAdd = "sheet-tunnel-editor-add"
    case tunnelEditorRoute = "sheet-tunnel-editor-route"
    case tunnelEditorEdit = "sheet-tunnel-editor-edit"
    case tunnelEditorFailure = "sheet-tunnel-editor-failure"
    case tunnelLog = "sheet-tunnel-log"
    case tunnelLogLong = "sheet-tunnel-log-long"

    @MainActor
    public func makeFixture() -> AppFixture {
        let needsApproval = [.httpsApproval, .httpsApprovalRunning, .httpsApprovalFailure].contains(self)
        let sites = InMemorySitesPort(setup: needsApproval ? .init() : SampleData.approvedSetup)
        let tunnels = InMemoryTunnelsPort()
        return AppFixture(suiteName: "dev.jerd.fixtures.snapshot", sites: sites, tunnels: tunnels)
    }

    /// Launches the fixture and opens the sheet.
    @MainActor
    public func prepare(_ fixture: AppFixture) async {
        await fixture.state.launch()
        switch self {
        case .siteEditorAdd, .siteEditorEdit, .siteEditorFailure: await prepareSiteEditor(fixture)
        case .httpsApproval, .httpsApprovalRunning, .httpsApprovalFailure: await prepareApproval(fixture)
        case .tunnelEditorAdd, .tunnelEditorRoute, .tunnelEditorEdit, .tunnelEditorFailure:
            await prepareTunnelEditor(fixture)
        case .tunnelLog, .tunnelLogLong:
            if self == .tunnelLogLong { await fixture.tunnels.configure { $0.logText = SampleData.longTunnelLog } }
            fixture.state.sites.tunnels.showLog(SampleData.previewTunnel)
        }
    }

    @MainActor
    public func isReady(_ fixture: AppFixture) -> Bool {
        let model = fixture.state.sites
        guard fixture.state.isLaunched else { return false }
        switch self {
        case .siteEditorFailure: return model.sheet?.editor?.failure != nil
        case .httpsApproval: return model.sheet?.approval != nil
        case .httpsApprovalRunning: return model.runningApprovalID != nil
        case .httpsApprovalFailure: return model.approvalFailure != nil
        case .tunnelEditorAdd, .tunnelEditorRoute: return model.tunnels.sheet?.editor?.metricsPort.isEmpty == false
        case .tunnelEditorFailure: return model.tunnels.sheet?.editor?.failure != nil
        default: return model.sheet != nil || model.tunnels.sheet != nil
        }
    }
}
