import Foundation
import JerdTunnels
import JerdWeb

extension TunnelsModel {
    /// Cloudflare's dashboard, where the user checks routes. Jerd never changes them.
    public static let cloudflareDashboard = URL(string: "https://one.dash.cloudflare.com/")

    /// Opens the editor for a new tunnel and asks for a free metrics port.
    public func beginAdd(sites: [Site]) {
        guard canChange else { return }
        let editor = TunnelEditorModel(tunnel: nil, sites: sites)
        sheet = .editor(editor)
        Task {
            do {
                editor.metricsPort = String(try await port.suggestedPort())
            } catch {
                editor.failure = ErrorText.message(for: error)
            }
        }
    }

    /// Opens the editor for a stopped tunnel.
    public func beginEdit(_ tunnel: TunnelRegistration, sites: [Site]) {
        guard canChange, !isActive(tunnel.id) else { return }
        sheet = .editor(TunnelEditorModel(tunnel: tunnel, sites: sites))
    }

    /// Closes the editor and forgets the typed token.
    public func cancelEditor() {
        sheet?.editor?.clearToken()
        sheet = nil
    }

    /// Saves the registration and its token. It never connects. A failure shows in the editor
    /// while it is open, else on the page; only a save from the open editor shows the tunnel.
    @discardableResult
    public func save(_ editor: TunnelEditorModel) -> Task<Void, Never>? {
        guard canChange, editor.canSave, let registration = editor.registration else { return nil }
        let token = editor.tokenToSave
        editor.failure = nil
        operation = .working("Saving \(registration.name)…")
        let task = Task {
            do {
                try await port.save(registration, token: token)
                editor.clearToken()
                operation = .idle
                startupFailures[registration.id] = nil
                if sheet?.editor === editor {
                    sheet = nil
                    shell.show(.item(.tunnel(registration.id)))
                }
            } catch {
                reportEditorFailure(ErrorText.message(for: error), editor: editor)
            }
            await refresh()
        }
        currentWork = task
        return task
    }

    /// A failed save shows in its editor while it is open. After Cancel it shows on the page.
    private func reportEditorFailure(_ message: String, editor: TunnelEditorModel) {
        if sheet?.editor === editor {
            editor.failure = message
            operation = .idle
        } else {
            operation = .failed(message: message)
        }
    }

    /// Runs the confirmed step and clears the confirmation.
    @discardableResult
    public func confirm() -> Task<Void, Never>? {
        guard let step = confirmation else { return nil }
        confirmation = nil
        switch step {
        case .connect(let tunnel, _):
            return perform("Connecting \(tunnel.name)…") { model in
                model.startupFailures[tunnel.id] = nil
                try await model.port.connect(id: tunnel.id)
            }
        case .remove(let tunnel):
            return perform("Removing \(tunnel.name)…") { model in
                if model.isActive(tunnel.id) { try await model.port.stop(id: tunnel.id) }
                try await model.port.remove(id: tunnel.id)
                model.startupFailures[tunnel.id] = nil
            }
        }
    }

    /// Stops one connector gracefully, outside the edit lock. Its failure belongs to the tunnel,
    /// so a running edit never hides it.
    @discardableResult
    public func stop(_ tunnel: TunnelRegistration) -> Task<Void, Never>? {
        guard canStop(tunnel.id) else { return nil }
        stoppingIDs.insert(tunnel.id)
        stopFailures[tunnel.id] = nil
        let task = Task {
            do {
                try await port.stop(id: tunnel.id)
            } catch {
                stopFailures[tunnel.id] = ErrorText.message(for: error)
            }
            stoppingIDs.remove(tunnel.id)
            stopWork[tunnel.id] = nil
            await refresh()
        }
        stopWork[tunnel.id] = task
        return task
    }

    /// Opens the connector log of a tunnel.
    public func showLog(_ tunnel: TunnelRegistration) {
        sheet = .log(TunnelLogModel(id: tunnel.id, name: tunnel.name, port: port))
    }

    /// Asks for a trusted cloudflared executable, then checks and uses it.
    @discardableResult
    public func chooseRuntime() -> Task<Void, Never>? {
        guard canChange else { return nil }
        return Task {
            let request = FilePanelRequest(
                kind: .executable,
                message: "Jerd will run this file to check its version. Select a file that you trust.",
                prompt: "Use Executable")
            guard let url = await panels.choose(request) else { return }
            await perform("Checking the selected cloudflared…") { model in
                _ = try await model.port.useRuntime(at: url)
            }?.value
        }
    }

    public func openInBrowser(_ tunnel: TunnelRegistration) {
        if let url = tunnel.publicURL { workspace.open(url) }
    }

    public func copyAddress(_ tunnel: TunnelRegistration) {
        clipboard.copy("https://\(tunnel.hostname)", confirmation: "Copied public address")
    }

    public func openCloudflare() {
        if let url = Self.cloudflareDashboard { workspace.open(url) }
    }
}
