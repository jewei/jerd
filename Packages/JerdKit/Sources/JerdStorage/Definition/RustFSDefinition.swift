import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// The managed-service definition of the one RustFS storage service.
///
/// Start steps after the shared lock, record, and version checks: start marker hashes, data
/// identity, and credentials (`StorageData`) → the launch plan. After the readiness and listener
/// checks, `initialized.json` records the runtime and the hashes.
///
/// RustFS gets loopback S3 and console listeners, its keys through the key-file flags (never in
/// an argument or the environment), and the fixed relative volume `data` from its private
/// working folder, because RustFS splits volume arguments at spaces and the data root has one.
/// Telemetry export and update checks are off.
public struct RustFSDefinition: ServiceDefinition {
    public let runtime: StorageRuntime
    public let ports: StoragePorts
    public let profile: ServiceProfile
    let layout: StorageLayout
    let launch: StorageLaunch
    let makeSession: @Sendable () -> S3Session
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - launch: the per-launch state that each start begins and each stop ends.
    ///   - makeSession: a new S3 transport for each launch.
    init(
        runtime: StorageRuntime, ports: StoragePorts, layout: StorageLayout, dataRoot: URL, launch: StorageLaunch,
        makeSession: @escaping @Sendable () -> S3Session, now: @escaping @Sendable () -> Date
    ) {
        self.runtime = runtime
        self.ports = ports
        self.layout = layout
        self.launch = launch
        self.makeSession = makeSession
        self.now = now
        profile = ServiceProfile(
            name: "RustFS", runtimeID: runtime.id, record: layout.record, containingDirectory: dataRoot,
            log: ServiceLog(file: layout.logFile, previousFile: layout.previousLogFile), ports: ports.ordered,
            messages: StorageMessages.instance)
    }

    /// The first line of `rustfs --version` must be `rustfs` and the saved version.
    public var versionProbe: VersionProbe {
        VersionProbe(
            request: ProcessRequest(
                executable: runtime.executable, arguments: ["--version"], workingDirectory: layout.root),
            rule: .firstLine(label: "rustfs", version: runtime.version),
            mismatchMessage: StorageMessages.versionMismatch)
    }

    var data: StorageData { StorageData(layout: layout) }

    /// Prepares the data, then begins a launch with a new S3 session. The launch ends (the
    /// session is invalidated and the names are cleared) in `didStop`, after every kind of stop.
    public func prepareStart(_ tools: StartTools) async throws -> LaunchPlan {
        let credentials = try data.prepare(for: runtime)
        let session = makeSession()
        let launch = launch
        let id = launch.begin(session)
        let client = S3Client(port: ports.api, credentials: credentials, sender: session.sender, now: now)
        let readiness = StorageReadinessProbe(
            client: client, console: session.sender, consoleURL: consoleURL, launch: launch, launchID: id)
        return LaunchPlan(
            request: serverRequest, ports: Set(ports.ordered), readiness: readiness.check,
            secrets: [credentials.secretKey], didStop: { launch.end(id) })
    }

    public func completeStart() async throws {
        try data.markInitialized(runtime)
    }

    var consoleURL: URL { StorageSettings(ports: ports).consoleURL }

    /// The exact RustFS command line and environment.
    var serverRequest: ProcessRequest {
        let origin = "http://127.0.0.1:\(ports.console)"
        return ProcessRequest(
            executable: runtime.executable,
            arguments: [
                "server", "--address", "127.0.0.1:\(ports.api)",
                "--console-enable", "--console-address", "127.0.0.1:\(ports.console)",
                "--access-key-file", layout.accessKeyFile.path, "--secret-key-file", layout.secretKeyFile.path,
                "--region", StorageSettings.region, ServiceFileName.data,
            ], workingDirectory: layout.root,
            environment: [
                "RUSTFS_OBS_TRACES_EXPORT_ENABLED": "false", "RUSTFS_OBS_METRICS_EXPORT_ENABLED": "false",
                "RUSTFS_OBS_LOGS_EXPORT_ENABLED": "false", "RUSTFS_OBS_LOGGER_LEVEL": "warn",
                "RUSTFS_OBS_PROFILING_EXPORT_ENABLED": "false", "RUSTFS_CHECK_UPDATE": "false",
                "RUSTFS_CONSOLE_CORS_ALLOWED_ORIGINS": origin, "RUSTFS_CORS_ALLOWED_ORIGINS": origin,
            ])
    }
}
