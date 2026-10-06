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
            try await runInitializer(request, credentials: credentials, tools: tools)
        } else {
            try OwnedDirectory.create(files.data, within: files.root)
        }
        // Only a setup phase needs a socket folder. Redis has none, so nothing can fail between
        // its data folder and its marker.
        let sockets = DatabaseSocketFolder.newPath(in: temporaryRoot)
        guard let setup = engine.setupPhase(credentials, sockets: sockets) else { return }
        try DatabaseSocketFolder.create(at: sockets, owner: files.root)
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

    /// Runs the initializer as an owned process of the instance (a run record, the lock held,
    /// a graceful stop). Its input files hold the password; the instance removes them when the
    /// wait for its exit ends.
    private func runInitializer(
        _ request: ProcessRequest, credentials: DatabaseCredentials, tools: StartTools
    ) async throws {
        let inputs = engine.initializerFiles(credentials)
        let plan = InitializerPlan(
            request: request, timeout: Self.initializationTimeout,
            timeoutMessage: DatabaseMessages.initializationTimedOut, secrets: [credentials.password],
            secretFiles: inputs.map(\.url))
        do {
            for input in inputs { try input.write() }
        } catch {
            throw plan.discard(after: error)
        }
        let result = try await tools.runInitializer(plan)
        guard result.succeeded else {
            let detail = result.output.isEmpty ? "Exit status \(result.status)." : result.output
            throw JerdError.processFailed("\(DatabaseMessages.initializationFailed) \(detail)")
        }
    }
}
