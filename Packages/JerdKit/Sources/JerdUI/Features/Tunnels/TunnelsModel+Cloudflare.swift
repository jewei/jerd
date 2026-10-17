import Foundation
import JerdTunnels

extension TunnelsModel {
    /// Cloudflare's API token page, where the user creates the token that Jerd asks for.
    public static let cloudflareTokenPage = URL(string: "https://dash.cloudflare.com/profile/api-tokens")

    /// Reads the Cloudflare connection and its domains into a new editor. A failed Keychain read
    /// shows the Connect field, so a new API token can replace the saved one. The domain load is an
    /// operation, so Disconnect cannot run while it waits.
    func loadCloudflare(into editor: TunnelEditorModel) async {
        let isConnected: Bool
        do {
            isConnected = try await port.isCloudflareConnected()
        } catch {
            editor.isCloudflareConnected = false
            editor.failure = ErrorText.message(for: error)
            return
        }
        editor.isCloudflareConnected = isConnected
        // Keep a failed port suggestion in view.
        if isConnected { await loadCloudflareZones(editor, clearsFailure: false)?.value }
    }

    /// Loads the domains of the connected account again, for example after a network failure.
    @discardableResult
    public func loadCloudflareZones(_ editor: TunnelEditorModel, clearsFailure: Bool = true) -> Task<Void, Never>? {
        guard canChange else { return nil }
        return runAccountStep("Loading Cloudflare domains…", editor: editor, clearsFailure: clearsFailure) { model in
            editor.useZones(try await model.port.cloudflareZones())
        }
    }

    /// Checks the typed API token, saves it, and shows its domains.
    @discardableResult
    public func connectCloudflare(_ editor: TunnelEditorModel) -> Task<Void, Never>? {
        guard canChange, let token = editor.apiTokenToConnect else { return nil }
        return runAccountStep("Connecting Cloudflare…", editor: editor) { model in
            editor.useZones(try await model.port.connectCloudflare(apiToken: token))
            editor.apiToken = ""
        }
    }

    /// Removes the saved API token. Tunnels and DNS records in Cloudflare stay.
    @discardableResult
    public func disconnectCloudflare(_ editor: TunnelEditorModel) -> Task<Void, Never>? {
        guard canChange else { return nil }
        return runAccountStep("Disconnecting Cloudflare…", editor: editor) { model in
            try await model.port.disconnectCloudflare()
            editor.forgetCloudflare()
        }
    }

    public func openCloudflareTokenPage() {
        if let url = Self.cloudflareTokenPage { workspace.open(url) }
    }

    /// Connects a tunnel that Jerd just created, so Create is one step. A failure shows on the page.
    /// After Cancel, Jerd never publishes the site: the created tunnel stays stopped.
    func connectCreated(_ tunnel: TunnelRegistration, afterCancel: Bool) async {
        guard !afterCancel else {
            operation = .failed(
                message: "Jerd created \(tunnel.name) in Cloudflare before Cancel took effect. It is not connected.")
            return
        }
        operation = .working("Connecting \(tunnel.name)…")
        do {
            try await port.connect(id: tunnel.id)
            operation = .idle
        } catch {
            operation = .failed(
                message: "Jerd created \(tunnel.name) in Cloudflare, but it did not connect. "
                    + ErrorText.message(for: error))
        }
    }

    private func runAccountStep(
        _ message: String, editor: TunnelEditorModel, clearsFailure: Bool = true,
        _ work: @escaping @MainActor (TunnelsModel) async throws -> Void
    ) -> Task<Void, Never> {
        if clearsFailure { editor.failure = nil }
        operation = .working(message)
        let task = Task {
            do {
                try await work(self)
                operation = .idle
            } catch {
                reportEditorFailure(ErrorText.message(for: error), editor: editor)
            }
        }
        currentWork = task
        return task
    }
}
