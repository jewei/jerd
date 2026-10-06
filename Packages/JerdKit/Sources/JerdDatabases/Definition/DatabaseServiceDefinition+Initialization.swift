import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

extension DatabaseServiceDefinition {
    var marker: InitializationMarker<DatabaseIdentity> {
        InitializationMarker(
            file: files.layout.initializedMarkerFile,
            messages: .init(mismatch: DatabaseMessages.initializedMismatch, interrupted: DatabaseMessages.interrupted))
    }

    /// `initialized` when the marker matches and `data/` is a real folder. Data without a marker is
    /// partial and is never initialized again.
    func initializationStatus() throws -> InitializationMarker<DatabaseIdentity>.Status {
        try marker.status(
            expected: identity, dataIsComplete: DataFolder.isRealDirectory(files.data),
            dataMayExist: FileProbe.presence(at: files.data).mayExist)
    }

    /// Creates new data: the initializer (or a plain data folder for Redis), then the setup phase.
    func initialize(_ credentials: DatabaseCredentials, tools: StartTools) async throws {
        if let request = engine.initializerRequest() {
            try await runInitializer(request, credentials: credentials)
        } else {
            try OwnedDirectory.create(files.data, within: files.root)
        }
        let sockets = try DatabaseSocketFolder.create(in: temporaryRoot)
        guard let setup = engine.setupPhase(credentials, sockets: sockets) else {
            try FileManager.default.removeItem(at: sockets)
            return
        }
        let plan = LaunchPlan(
            request: setup.server, ports: [],
            readiness: DatabaseReadiness.check(
                client: setup.client, reply: engine.healthCheck.reply, password: credentials.password,
                commands: tools.commands),
            secrets: [credentials.password], temporaryItems: [sockets], secretFiles: setup.files.map(\.url))
        do {
            for file in setup.files { try file.write() }
        } catch {
            throw plan.discard(after: error)
        }
        // The instance removes the setup files when the readiness check ends, and the socket
        // folder when the setup server stops.
        try await tools.runSetupPhase(plan)
    }

    /// Runs the initializer with its private input files, which are removed on every exit path.
    private func runInitializer(_ request: ProcessRequest, credentials: DatabaseCredentials) async throws {
        let inputs = engine.initializerFiles(credentials)
        defer {
            // The files hold the password (mode 0600). A failed removal leaves them private.
            for input in inputs { try? AtomicFile.remove(input.url) }
        }
        for input in inputs { try input.write() }
        let result = try await initializationCommands.run(request, timeout: Self.initializationTimeout)
        guard result.succeeded else {
            let detail = LogRedactor.redact(result.diagnosticOutput, values: [credentials.password])
            throw JerdError.processFailed("\(DatabaseMessages.initializationFailed) \(detail.suffix(4_096))")
        }
    }
}
