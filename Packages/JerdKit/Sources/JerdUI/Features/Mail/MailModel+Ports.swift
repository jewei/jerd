import JerdMail

extension MailModel {
    /// Opens the ports sheet with the saved ports.
    public func editPorts() {
        guard canEditPorts else { return }
        portsOperation = .idle
        portsDraft = PortsDraft(first: settings.smtpPort, second: settings.webPort)
    }

    /// Fills both fields with free ports.
    @discardableResult
    public func suggestPorts() -> Task<Void, Never>? {
        guard portsDraft != nil, !portsOperation.isWorking else { return nil }
        portsOperation = .working("Finding free ports…")
        return Task {
            do {
                let ports = try await port.suggestedPorts()
                portsDraft = portsDraft.map { _ in PortsDraft(first: ports.smtp, second: ports.web) }
                portsOperation = .idle
            } catch {
                portsOperation = .failed(message: ErrorText.message(for: error))
            }
        }
    }

    /// Saves the ports and closes the sheet. A failure stays in the sheet.
    @discardableResult
    public func savePorts() -> Task<Void, Never>? {
        guard let ports = portsDraft?.ports, canEditPorts, !portsOperation.isWorking else { return nil }
        portsOperation = .working("Saving ports…")
        let task = Task {
            do {
                try await port.edit(ports: MailPorts(smtp: ports.first, web: ports.second))
                await refresh()
                portsDraft = nil
                portsOperation = .idle
            } catch {
                portsOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        currentTask = task
        return task
    }

    /// Closes the sheet. A save in progress finishes; only the wait ends.
    public func cancelPorts() {
        portsDraft = nil
        portsOperation = .idle
    }
}
