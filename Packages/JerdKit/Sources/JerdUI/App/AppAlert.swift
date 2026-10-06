/// A window alert. Only a cancelled quit and a failed system setup use one; every other error
/// shows once, inline, on the page that owns the failed operation.
public struct AppAlert: Identifiable, Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public var id: String { title + "\n" + message }

    /// The alert after a stage of the quit could not stop safely.
    public static func quitCancelled(_ message: String) -> AppAlert {
        AppAlert(title: "Jerd Stayed Open", message: message)
    }
}
