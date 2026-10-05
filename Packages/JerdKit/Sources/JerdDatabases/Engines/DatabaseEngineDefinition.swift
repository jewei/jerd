import Foundation
import JerdProcess

/// The pure, engine-specific part of a database service: exact arguments, environment, and
/// configuration files. A password never appears in an argument.
public protocol DatabaseEngineDefinition: Sendable {
    var runtime: DatabaseRuntime { get }
    var service: DatabaseService { get }
    var files: DatabaseInstanceFiles { get }

    /// The server request. `sockets` is the private socket folder of this launch.
    func serverRequest(sockets: URL) -> ProcessRequest
    /// The command that creates new data, or nil when the data folder is created directly.
    func initializerRequest() -> ProcessRequest?
    /// Private files that the initializer reads. They are removed when the initializer ends.
    func initializerFiles(_ credentials: DatabaseCredentials) -> [EngineFile]
    /// The configuration with the password, written before every launch so a port change applies.
    func configuration(_ credentials: DatabaseCredentials, sockets: URL) -> EngineFile
    /// A client request that runs `command` against the TCP listener.
    func clientRequest(_ command: [String], credentials: DatabaseCredentials) -> ProcessRequest
    /// The second step of a first start, or nil. See `DatabaseSetupPhase`.
    func setupPhase(_ credentials: DatabaseCredentials, sockets: URL) -> DatabaseSetupPhase?
    /// The readiness command and its exact reply.
    var healthCheck: (command: [String], reply: String) { get }
}

extension DatabaseEngineDefinition {
    public func initializerFiles(_ credentials: DatabaseCredentials) -> [EngineFile] { [] }

    public func setupPhase(_ credentials: DatabaseCredentials, sockets: URL) -> DatabaseSetupPhase? { nil }

    /// A request for an executable in the runtime, with the instance folder as working folder.
    func request(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) -> ProcessRequest {
        ProcessRequest(
            executable: runtime.executable(executable), arguments: arguments, workingDirectory: files.root,
            environment: environment)
    }
}
