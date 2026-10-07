/// One progress report of an installation, for the Runtimes page.
public struct RuntimeInstallProgress: Equatable, Sendable {
    public let message: String
    /// 0…1, or nil for a step without a known length.
    public let fraction: Double?

    public init(_ message: String, _ fraction: Double? = nil) {
        self.message = message
        self.fraction = fraction
    }
}
