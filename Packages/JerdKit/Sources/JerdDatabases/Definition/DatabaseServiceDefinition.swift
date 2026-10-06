import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// The managed-service definition of one database instance.
///
/// Start steps after the shared lock, record, and version checks: data identity
/// (`runtime.json`) → credentials → first initialization (`initialized.json`) → engine
/// configuration and a new socket folder → the launch plan.
public struct DatabaseServiceDefinition: ServiceDefinition {
    /// The limit of `initdb` and `mysqld --initialize-insecure`.
    public static let initializationTimeout: Duration = .seconds(120)

    public let engine: any DatabaseEngineDefinition
    public let profile: ServiceProfile
    let temporaryRoot: URL

    /// - Parameter temporaryRoot: where socket folders are made (`$TMPDIR` in the app).
    public init(service: DatabaseService, runtime: DatabaseRuntime, layout: DatabasesLayout, temporaryRoot: URL) {
        let instance = layout.instance(service.id)
        engine = Self.engine(runtime: runtime, service: service, files: DatabaseInstanceFiles(layout: instance))
        profile = ServiceProfile(
            name: service.name, runtimeID: runtime.id, record: instance.record, containingDirectory: layout.root,
            log: ServiceLog(file: instance.logFile, previousFile: instance.previousLogFile), ports: [service.port],
            stopSignal: runtime.engine.stopSignal, messages: DatabaseMessages.instance)
        self.temporaryRoot = temporaryRoot
    }

    /// The engine definition for the engine of `runtime`.
    public static func engine(
        runtime: DatabaseRuntime, service: DatabaseService, files: DatabaseInstanceFiles
    )
        -> any DatabaseEngineDefinition
    {
        switch runtime.engine {
        case .mysql: MySQLDefinition(runtime: runtime, service: service, files: files)
        case .postgresql: PostgresDefinition(runtime: runtime, service: service, files: files)
        case .redis: RedisDefinition(runtime: runtime, service: service, files: files)
        }
    }

    /// `<server> --version` must name the registered version as a whole token.
    public var versionProbe: VersionProbe {
        VersionProbe(
            request: engine.request(engine.runtime.engine.serverName, ["--version"]),
            rule: .standalone(version: engine.runtime.version), mismatchMessage: DatabaseMessages.versionMismatch)
    }

    public var identity: DatabaseIdentity { DatabaseIdentity(service: engine.service, runtime: engine.runtime) }
    var files: DatabaseInstanceFiles { engine.files }

    public func prepareStart(_ tools: StartTools) async throws -> LaunchPlan {
        let identityGuard = DataIdentityGuard<DatabaseIdentity>(
            file: files.layout.runtimeIdentityFile,
            messages: .init(mismatch: DatabaseMessages.identityMismatch, untracked: DatabaseMessages.untracked))
        try identityGuard.admit(identity, dataIsUntouched: FileProbe.presence(at: files.data) == .absent)
        let credentials = try loadCredentials()
        if try initializationStatus() == .uninitialized {
            try await initialize(credentials, tools: tools)
            try marker.write(identity)
        }
        return try servicePlan(credentials, commands: tools.commands)
    }

    /// Reads the saved credentials, or creates them for new data only.
    func loadCredentials() throws -> DatabaseCredentials {
        if FileProbe.presence(at: files.layout.credentialsFile).mayExist {
            return try DatabaseCredentials.read(from: files.layout.credentialsFile)
        }
        guard FileProbe.presence(at: files.data) == .absent else { throw DatabaseMessages.credentialsMissing }
        let credentials = try DatabaseCredentials.generate()
        try credentials.write(to: files.layout.credentialsFile)
        return credentials
    }

    /// The plan of the TCP server: a new socket folder and the engine configuration.
    func servicePlan(_ credentials: DatabaseCredentials, commands: any CommandRunning) throws -> LaunchPlan {
        let sockets = try DatabaseSocketFolder.create(in: temporaryRoot)
        let plan = LaunchPlan(
            request: engine.serverRequest(sockets: sockets), ports: [engine.service.port],
            readiness: DatabaseReadiness.check(
                client: engine.clientRequest(engine.healthCheck.command, credentials: credentials),
                reply: engine.healthCheck.reply, password: credentials.password, commands: commands),
            secrets: [credentials.password], temporaryItems: [sockets])
        do {
            try engine.configuration(credentials, sockets: sockets).write()
        } catch {
            throw plan.discard(after: error)
        }
        return plan
    }
}
