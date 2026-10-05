/// A code-signing designated requirement that an app from a disk image must satisfy (fixes P-I5).
public struct CodeRequirement: Sendable, Equatable {
    /// The requirement language text, as `codesign -d -r-` prints it.
    public let text: String
    /// The publisher name for messages.
    public let publisher: String

    public init(text: String, publisher: String) {
        self.text = text
        self.publisher = publisher
    }

    /// Postgres.app, signed with Developer ID by its maintainer (team ZF84SJ5A3G).
    public static let postgresApp = CodeRequirement(
        text: #"identifier "com.postgresapp.Postgres2" and anchor apple generic"#
            + #" and certificate 1[field.1.2.840.113635.100.6.2.6] exists"#
            + #" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#
            + #" and certificate leaf[subject.OU] = "ZF84SJ5A3G""#,
        publisher: "Postgres.app")

    /// The `codesign` arguments that verify `path` deeply and strictly against this requirement.
    public func verifyArguments(for path: String) -> [String] {
        ["--verify", "--deep", "--strict", "-R", "=\(text)", path]
    }
}
