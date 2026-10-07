/// The release signature record of a payload.
public struct PayloadSigning: Codable, Equatable, Sendable {
    /// The Apple Developer team that signed every Mach-O file.
    public let teamID: String
    /// The SHA-256 of the receipt before signing, which ties the signed payload to its prepared source.
    public let sourceReceiptSHA256: String

    public init(teamID: String, sourceReceiptSHA256: String) {
        self.teamID = teamID
        self.sourceReceiptSHA256 = sourceReceiptSHA256
    }
}
