/// The HTTP transport of one RustFS launch, and the step that releases it.
struct S3Session: Sendable {
    let sender: any S3Sending
    /// Releases the transport, for example invalidates its URL session. It runs once, when the
    /// launch ends.
    let end: @Sendable () -> Void

    /// A new `S3Transport` that the end of the launch invalidates.
    static func transport() -> S3Session {
        let transport = S3Transport()
        return S3Session(sender: transport, end: { transport.invalidate() })
    }

    /// A sender that every launch shares, for example a test server. The end of a launch keeps it.
    static func shared(_ sender: any S3Sending) -> S3Session {
        S3Session(sender: sender, end: {})
    }
}
