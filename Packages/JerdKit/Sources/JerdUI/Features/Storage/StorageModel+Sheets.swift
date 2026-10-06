import JerdStorage

extension StorageModel {
    /// True while the Add Bucket or the ports sheet shows.
    public var isShowingSheet: Bool { bucketDraft != nil || portsDraft != nil }

    /// Why the storage controls are off after the user cancelled a sheet whose save still
    /// runs, or nil. The page shows it, because the closed sheet cannot.
    public var cancelledSaveMessage: String? {
        let bucketRuns = bucketOperation.isWorking && bucketDraft == nil
        let portsRun = portsOperation.isWorking && portsDraft == nil
        return bucketRuns || portsRun ? CancelledSave.pendingMessage("Storage controls") : nil
    }

    /// Opens the Add Bucket sheet with a private bucket.
    public func beginAddBucket() {
        guard canAddBucket else { return }
        bucketOperation = .idle
        bucketDraft = BucketDraft()
    }

    /// Saves the bucket: storage starts when needed, then RustFS creates and verifies it. The new
    /// bucket is selected. A failure stays in the sheet. After Cancel, the result only refreshes
    /// the page.
    @discardableResult
    public func saveBucket() -> Task<Void, Never>? {
        guard let draft = bucketDraft, draft.canSave(in: settings), canAddBucket else { return nil }
        let name = draft.trimmedName
        bucketOperation = .working("Preparing bucket…")
        let task = running.run { [self] in
            do {
                try await port.addBucket(name: name, publicRead: draft.publicRead)
                await refresh()
                guard !Task.isCancelled else { return endCancelledBucket(failure: nil) }
                bucketOperation = .idle
                bucketDraft = nil
                navigate?(.item(.bucket(name)))
            } catch {
                await refresh()
                guard !Task.isCancelled else { return endCancelledBucket(failure: error) }
                bucketOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        bucketTask = task
        return task
    }

    /// Closes the sheet. A running save is asked to stop and keeps storage locked until it ends,
    /// so its late result cannot reach a newer sheet.
    public func cancelAddBucket() {
        bucketDraft = nil
        if bucketOperation.isWorking {
            bucketTask?.cancel()
        } else {
            bucketOperation = .idle
        }
    }

    private func endCancelledBucket(failure: (any Error)?) {
        bucketOperation = .idle
        bucketTask = nil
        if let page = CancelledSave.pageOperation(failure: failure) { operation = page }
    }

    public func editPorts() {
        guard canEditPorts else { return }
        portsOperation = .idle
        portsDraft = PortsDraft(first: settings.apiPort, second: settings.consolePort)
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
                portsDraft = PortsDraft(first: ports.api, second: ports.console)
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
                try await port.edit(ports: StoragePorts(api: ports.first, console: ports.second))
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

    /// Closes the ports sheet, with the same rule as `cancelAddBucket()`.
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
