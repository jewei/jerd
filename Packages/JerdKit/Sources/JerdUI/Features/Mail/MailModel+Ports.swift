import JerdMail

extension MailModel {
    /// Why the mail controls are off after the user cancelled the ports sheet while its save
    /// still runs, or nil. The page shows it, because the closed sheet cannot.
    public var cancelledSaveMessage: String? {
        portsOperation.isWorking && portsDraft == nil ? CancelledSave.pendingMessage("Mail controls") : nil
    }

    /// Opens the ports sheet with the saved ports.
    public func editPorts() {
        guard canEditPorts else { return }
        portsOperation = .idle
        portsDraft = PortsDraft(first: settings.smtpPort, second: settings.webPort)
    }

    /// Fills both fields with free ports. After Cancel, the result is dropped: nothing changed.
    @discardableResult
    public func suggestPorts() -> Task<Void, Never>? {
        guard portsDraft != nil, !portsOperation.isWorking else { return nil }
        portsOperation = .working("Finding free ports…")
        let task = running.run { [self] in
            do {
                let ports = try await port.suggestedPorts()
                guard !Task.isCancelled else { return endCancelledPorts(failure: nil) }
                portsDraft = PortsDraft(first: ports.smtp, second: ports.web)
                portsOperation = .idle
            } catch {
                guard !Task.isCancelled else { return endCancelledPorts(failure: nil) }
                portsOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        portsTask = task
        return task
    }

    /// Saves the ports and closes the sheet. A failure stays in the sheet; after Cancel it shows
    /// as the page banner.
    @discardableResult
    public func savePorts() -> Task<Void, Never>? {
        guard let ports = portsDraft?.ports, canEditPorts else { return nil }
        portsOperation = .working("Saving ports…")
        let task = running.run { [self] in
            do {
                try await port.edit(ports: MailPorts(smtp: ports.first, web: ports.second))
                await refresh()
                guard !Task.isCancelled else { return endCancelledPorts(failure: nil) }
                portsOperation = .idle
                portsDraft = nil
            } catch {
                guard !Task.isCancelled else { return endCancelledPorts(failure: error) }
                portsOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        portsTask = task
        return task
    }

    /// Closes the sheet. A running save is asked to stop and keeps mail locked until it ends,
    /// so its late result cannot reach a newer sheet.
    public func cancelPorts() {
        portsDraft = nil
        if portsOperation.isWorking {
            portsTask?.cancel()
        } else {
            portsOperation = .idle
        }
    }

    private func endCancelledPorts(failure: (any Error)?) {
        portsOperation = .idle
        portsTask = nil
        if let page = CancelledSave.pageOperation(failure: failure) { operation = page }
    }
}
