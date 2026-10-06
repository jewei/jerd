import Foundation
import JerdUI

/// A named state of one Sites or tunnel sheet, for snapshots. The offscreen window cannot show
/// a sheet, so each sheet renders alone at its own width.
public enum SitesSheetScenario: String, CaseIterable, Sendable {
    case siteEditorAdd = "sheet-site-editor-add"
    case siteEditorEdit = "sheet-site-editor-edit"
    case httpsApproval = "sheet-https-approval"
    case tunnelEditorAdd = "sheet-tunnel-editor-add"
    case tunnelEditorEdit = "sheet-tunnel-editor-edit"
    case tunnelLog = "sheet-tunnel-log"

    @MainActor
    public func makeFixture() -> AppFixture {
        let sites = InMemorySitesPort(setup: self == .httpsApproval ? .init() : SampleData.approvedSetup)
        return AppFixture(suiteName: "dev.jerd.fixtures.snapshot", sites: sites)
    }

    /// Launches the fixture and opens the sheet.
    @MainActor
    public func prepare(_ fixture: AppFixture) async {
        await fixture.state.launch()
        let model = fixture.state.sites
        switch self {
        case .siteEditorAdd:
            await fixture.sites.configure { port in
                port.suggestions["\(SampleData.user)/Projects/aurora"] = .init(
                    path: "\(SampleData.user)/Projects/aurora", isLaravel: false)
            }
            model.beginAdd()
            model.sheet?.editor?.useProjectFolder("\(SampleData.user)/Projects/aurora")
            await model.sheet?.editor?.inspect()
        case .siteEditorEdit:
            model.beginEdit(SampleData.studio)
        case .httpsApproval:
            await model.startAll()?.value
        case .tunnelEditorAdd:
            model.tunnels.beginAdd(sites: model.sites)
        case .tunnelEditorEdit:
            model.tunnels.beginEdit(SampleData.docsTunnel, sites: model.sites)
        case .tunnelLog:
            model.tunnels.showLog(SampleData.previewTunnel)
        }
    }

    @MainActor
    public func isReady(_ fixture: AppFixture) -> Bool {
        let model = fixture.state.sites
        guard fixture.state.isLaunched else { return false }
        switch self {
        case .tunnelEditorAdd: return model.tunnels.sheet?.editor?.metricsPort.isEmpty == false
        case .httpsApproval: return model.sheet?.approval != nil
        default: return model.sheet != nil || model.tunnels.sheet != nil
        }
    }
}
