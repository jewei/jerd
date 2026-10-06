/// The one tunnel sheet: the editor or the connector log.
public enum TunnelsSheet: Identifiable {
    case editor(TunnelEditorModel)
    case log(TunnelLogModel)

    public var id: String {
        switch self {
        case .editor(let editor): "editor.\(editor.id.uuidString)"
        case .log(let log): "log.\(log.id.uuidString)"
        }
    }

    @MainActor public var editor: TunnelEditorModel? {
        if case .editor(let editor) = self { return editor }
        return nil
    }
}
