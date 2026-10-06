import JerdProcess

extension S3Signer: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The public parts and a placeholder, so a log line, `dump`, or a test failure of a value
    /// that holds a signer (for example `S3Client`) never shows the secret key.
    var description: String {
        "S3Signer(accessKey: \(accessKey), secretKey: \(LogRedactor.marker), region: \(region), service: \(service))"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "accessKey": accessKey, "secretKey": LogRedactor.marker, "region": region, "service": service,
            ])
    }
}
