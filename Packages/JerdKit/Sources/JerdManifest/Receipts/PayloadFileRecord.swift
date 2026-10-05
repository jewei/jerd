/// The SHA-256 and the executable flag of one payload file.
public struct PayloadFileRecord: Codable, Hashable, Sendable {
    /// Lowercase hexadecimal SHA-256 of the file bytes.
    public let sha256: String
    /// True when the installed file gets mode 0700, false for mode 0600.
    public let executable: Bool

    public init(sha256: String, executable: Bool) {
        self.sha256 = sha256
        self.executable = executable
    }
}
