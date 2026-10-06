import Foundation
import JerdWeb

extension SitesModel {
    /// Opens the editor for a new site.
    public func beginAdd() {
        guard canChange else { return }
        sheet = .editor(SiteEditorModel(site: nil, configuration: configuration, port: port, panels: panels))
    }

    /// Opens the editor for a registered site.
    public func beginEdit(_ site: Site) {
        guard canChange else { return }
        sheet = .editor(SiteEditorModel(site: site, configuration: configuration, port: port, panels: panels))
    }

    /// Closes the editor. Running work continues; the operation banner can stop it.
    public func cancelEditor() {
        if sheet?.editor != nil { sheet = nil }
    }

    /// Saves the editor's site. A new site starts when the environment is stopped. A failure
    /// shows in the editor while it is open, else on the page.
    @discardableResult
    public func save(_ editor: SiteEditorModel) -> Task<Void, Never>? {
        guard canChange, editor.canSave else { return nil }
        let site = editor.draft
        editor.failure = nil
        return startWork("Saving \(site.displayName)…", canStop: true) { [self] in
            do {
                let outcome = try await port.apply(
                    .save(site, confirmed: editor.confirmsRoot), startIfStopped: editor.isNew)
                operation = .idle
                finishSave(outcome, site: site, editor: editor)
            } catch is CancellationError {
                operation = .idle
            } catch {
                reportEditorFailure(ErrorText.message(for: error), editor: editor)
            }
        }
    }

    /// Changes "Include when starting all sites".
    @discardableResult
    public func setEnabled(_ site: Site, _ isEnabled: Bool) -> Task<Void, Never>? {
        perform(isEnabled ? "Enabling \(site.displayName)…" : "Disabling \(site.displayName)…", canStop: true) {
            model in
            model.accept(try await model.port.apply(.enabled(site.id, isEnabled), startIfStopped: false))
        }
    }

    /// Asks before a registration is removed.
    public func requestRemoval(_ site: Site) {
        guard canChange else { return }
        confirmation = .removeSite(site)
    }

    private func finishSave(_ outcome: SiteChangeOutcome, site: Site, editor: SiteEditorModel) {
        accept(outcome)
        guard case .committed = outcome else { return }
        if sheet?.editor === editor { sheet = nil }
        shell.show(.item(.site(site.id)))
    }

    private func reportEditorFailure(_ message: String, editor: SiteEditorModel) {
        if sheet?.editor === editor {
            editor.failure = message
            operation = .idle
        } else {
            operation = .failed(message: message)
        }
    }
}
