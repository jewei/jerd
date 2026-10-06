import JerdProcess

extension StorageCredentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The access key and a placeholder, so a log line, `dump`, or a test failure never shows the
    /// secret key.
    public var description: String {
        "StorageCredentials(accessKey: \(accessKey), secretKey: \(LogRedactor.marker))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["accessKey": accessKey, "secretKey": LogRedactor.marker])
    }
}
