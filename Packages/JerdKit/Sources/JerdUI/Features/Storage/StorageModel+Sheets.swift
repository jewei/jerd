import JerdStorage

extension StorageModel {
    /// Opens the Add Bucket sheet with a private bucket.
    public func beginAddBucket() {
        guard canAddBucket else { return }
        bucketOperation = .idle
        bucketDraft = BucketDraft()
    }

    /// Saves the bucket: storage starts when needed, then RustFS creates and verifies it. The new
    /// bucket is selected. A failure stays in the sheet.
    @discardableResult
    public func saveBucket() -> Task<Void, Never>? {
        guard let draft = bucketDraft, draft.canSave(in: settings), canAddBucket else { return nil }
        let name = draft.trimmedName
        bucketOperation = .working("Preparing bucket…")
        let task = Task {
            do {
                try await port.addBucket(name: name, publicRead: draft.publicRead)
                await refresh()
                bucketDraft = nil
                bucketOperation = .idle
                navigate?(.item(.bucket(name)))
            } catch {
                await refresh()
                bucketOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        currentTask = task
        return task
    }

    public func cancelAddBucket() {
        bucketDraft = nil
        bucketOperation = .idle
    }

    public func editPorts() {
        guard canEditPorts else { return }
        portsOperation = .idle
        portsDraft = PortsDraft(first: settings.apiPort, second: settings.consolePort)
    }

    @discardableResult
    public func suggestPorts() -> Task<Void, Never>? {
        guard portsDraft != nil, !portsOperation.isWorking else { return nil }
        portsOperation = .working("Finding free ports…")
        return Task {
            do {
                let ports = try await port.suggestedPorts()
                portsDraft = portsDraft.map { _ in PortsDraft(first: ports.api, second: ports.console) }
                portsOperation = .idle
            } catch {
                portsOperation = .failed(message: ErrorText.message(for: error))
            }
        }
    }

    @discardableResult
    public func savePorts() -> Task<Void, Never>? {
        guard let ports = portsDraft?.ports, canEditPorts, !portsOperation.isWorking else { return nil }
        portsOperation = .working("Saving ports…")
        let task = Task {
            do {
                try await port.edit(ports: StoragePorts(api: ports.first, console: ports.second))
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

    public func cancelPorts() {
        portsDraft = nil
        portsOperation = .idle
    }
}
