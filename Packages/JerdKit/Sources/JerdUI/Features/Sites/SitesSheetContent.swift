import SwiftUI

/// The content of the open Sites or tunnel sheet, without the presentation. The page presents
/// it as a sheet; snapshots render it alone.
public struct SitesSheetContent: View {
    let model: SitesModel

    public init(model: SitesModel) {
        self.model = model
    }

    public var body: some View {
        if let sheet = model.sheet {
            switch sheet {
            case .editor(let editor): SiteEditorSheet(model: model, editor: editor)
            case .approval(let approval): HTTPSApprovalSheet(model: model, approval: approval)
            }
        } else if let sheet = model.tunnels.sheet {
            switch sheet {
            case .editor(let editor): TunnelEditorSheet(model: model.tunnels, editor: editor)
            case .log(let log): TunnelLogSheet(model: model.tunnels, log: log)
            }
        }
    }
}
