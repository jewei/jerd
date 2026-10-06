/// The one sheet of the Sites page. One value, so the editor can hand over to the HTTPS
/// approval without two sheets on screen at once.
public enum SitesSheet: Identifiable {
    case editor(SiteEditorModel)
    case approval(HTTPSApproval)

    public var id: String {
        switch self {
        case .editor(let editor): "editor.\(editor.id.uuidString)"
        case .approval(let approval): "approval.\(approval.id.uuidString)"
        }
    }

    /// The waiting approval, when the sheet shows one.
    public var approval: HTTPSApproval? {
        if case .approval(let approval) = self { return approval }
        return nil
    }

    /// The open editor, when the sheet shows one.
    @MainActor public var editor: SiteEditorModel? {
        if case .editor(let editor) = self { return editor }
        return nil
    }
}
