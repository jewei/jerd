import Foundation
import JerdMail

extension MailModel {
    @discardableResult
    public func start() -> Task<Void, Never>? {
        guard canStart else { return nil }
        return perform("Starting mail…") { try await $0.port.start() }
    }

    /// Stops the inbox, or tries again to stop one that did not stop.
    @discardableResult
    public func stop() -> Task<Void, Never>? {
        guard canStop else { return nil }
        return perform("Stopping mail…") { try await $0.port.stop() }
    }

    @discardableResult
    public func sendTestEmail() -> Task<Void, Never>? {
        guard canSendTestEmail else { return nil }
        return perform("Sending a test email…") { model in
            try await model.port.sendTestEmail()
            model.testResult = Self.testCaptured
        }
    }

    public func openInbox() {
        guard canOpenInbox else { return }
        workspace.open(settings.inboxURL)
    }

    public func copyEnvironment() {
        clipboard.copy(settings.laravelEnvironment, confirmation: "Copied Laravel settings")
    }

    public func copyInboxURL() {
        clipboard.copy(settings.inboxURL.absoluteString, confirmation: "Copied inbox URL")
    }

    public func copySMTPPort() {
        clipboard.copy(String(settings.smtpPort), confirmation: "Copied SMTP port")
    }

    public func revealInbox() {
        guard let files, files.hasDataFolder else { return }
        workspace.reveal(files.dataFolder)
    }

    public func openLog() {
        guard let files, files.hasLog else { return }
        workspace.open(files.log)
    }

    public func showRuntimes() {
        navigate?(.dashboard(.runtimes))
    }
}
