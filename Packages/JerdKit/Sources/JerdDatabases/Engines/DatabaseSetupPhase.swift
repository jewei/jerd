import JerdProcess

/// A temporary server of a first start, for example the MySQL socket-only bootstrap. It must
/// become ready with `client`, open no TCP listener, and stop before the real launch.
package struct DatabaseSetupPhase: Sendable {
    /// Private files of the phase, with the password. They are removed when its readiness check ends.
    package let files: [EngineFile]
    package let server: ProcessRequest
    /// The readiness client of the phase. Its reply must equal the engine health reply.
    package let client: ProcessRequest

    package init(files: [EngineFile], server: ProcessRequest, client: ProcessRequest) {
        self.files = files
        self.server = server
        self.client = client
    }
}
