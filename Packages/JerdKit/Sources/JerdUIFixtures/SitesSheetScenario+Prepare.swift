import Foundation
import JerdUI

extension SitesSheetScenario {
    /// Add Site with an inspected plain PHP folder, Edit Site, or an Edit Site whose save failed.
    @MainActor
    func prepareSiteEditor(_ fixture: AppFixture) async {
        let model = fixture.state.sites
        switch self {
        case .siteEditorAdd:
            let aurora = "\(SampleData.user)/Projects/aurora"
            await fixture.sites.configure { $0.suggestions[aurora] = .init(path: aurora, isLaravel: false) }
            model.beginAdd()
            model.sheet?.editor?.useProjectFolder(aurora)
            await model.sheet?.editor?.inspect()
        case .siteEditorFailure:
            model.beginEdit(SampleData.studio)
            guard let editor = model.sheet?.editor else { return }
            editor.isRootConfirmed = true
            await fixture.sites.configure {
                $0.failure = "Another site already uses studio.test. Choose a different hostname."
            }
            await model.save(editor)?.value
        default:
            model.beginEdit(SampleData.studio)
        }
    }

    /// The approval of a Start All: waiting, running (held at the macOS prompt), or failed.
    @MainActor
    func prepareApproval(_ fixture: AppFixture) async {
        let model = fixture.state.sites
        await model.startAll()?.value
        guard let approval = model.sheet?.approval else { return }
        switch self {
        case .httpsApprovalRunning:
            await fixture.sites.configure { $0.approvalGate = FixtureGate() }
            model.approve(approval)
        case .httpsApprovalFailure:
            await fixture.sites.configure {
                $0.failure =
                    "Allow Jerd in System Settings → General → Login Items & Extensions, then retry the operation."
            }
            await model.approve(approval)?.value
        default:
            break
        }
    }

    /// Add Tunnel (empty, or filled without the route confirmation), Edit Tunnel, or an Edit
    /// Tunnel whose save failed.
    @MainActor
    func prepareTunnelEditor(_ fixture: AppFixture) async {
        let model = fixture.state.sites.tunnels
        switch self {
        case .tunnelEditorAdd, .tunnelEditorRoute:
            model.beginAdd(sites: fixture.state.sites.sites)
            guard self == .tunnelEditorRoute, let editor = model.sheet?.editor else { return }
            editor.name = "Aurora preview"
            editor.hostname = "aurora.example.com"
            editor.token = "token"
        case .tunnelEditorFailure:
            model.beginEdit(SampleData.docsTunnel, sites: fixture.state.sites.sites)
            guard let editor = model.sheet?.editor else { return }
            editor.routeChecked = true
            await fixture.tunnels.configure { $0.failure = "This Cloudflare tunnel is already saved in Jerd." }
            await model.save(editor)?.value
        default:
            model.beginEdit(SampleData.docsTunnel, sites: fixture.state.sites.sites)
        }
    }
}
