/// Whether a service feature has read its saved settings. A failed load keeps the file and
/// blocks every change, so Jerd never replaces settings that it could not read.
public enum ServiceLoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed(message: String)

    public var isLoaded: Bool { self == .loaded }

    /// The message of a failed load.
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
