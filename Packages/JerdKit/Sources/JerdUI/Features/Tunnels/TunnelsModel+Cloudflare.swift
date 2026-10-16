import Foundation
import JerdTunnels

extension TunnelsModel {
    /// Cloudflare's API token page, where the user creates the token that Jerd asks for.
    public static let cloudflareTokenPage = URL(string: "https://dash.cloudflare.com/profile/api-tokens")

    /// Reads the Cloudflare connection and its domains into a new editor. A failure shows in the
    /// editor; "Use an existing token" still works.
    func loadCloudflare(into editor: TunnelEditorModel) async {
        do {
            guard try await port.isCloudflareConnected() else {
                editor.isCloudflareConnected = false
                return
            }
            editor.isCloudflareConnected = true
            editor.useZones(try await port.cloudflareZones())
        } catch {
            editor.failure = ErrorText.message(for: error)
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
        _ message: String, editor: TunnelEditorModel,
        _ work: @escaping @MainActor (TunnelsModel) async throws -> Void
    ) -> Task<Void, Never> {
        editor.failure = nil
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
