/// The text and the kind of item of one open panel.
public struct FilePanelRequest: Equatable, Sendable {
    /// What the panel selects.
    public enum Kind: Equatable, Sendable {
        /// One executable file.
        case executable
        /// One folder.
        case folder
    }

    public let kind: Kind
    /// The instruction at the top of the panel, for example "Select a trusted Caddy 2 executable."
    public let message: String
    /// The title of the confirm button.
    public let prompt: String

    public init(kind: Kind, message: String, prompt: String) {
        self.kind = kind
        self.message = message
        self.prompt = prompt
    }

    /// A request for a trusted executable, with the standard prompt.
    public static func executable(_ message: String) -> FilePanelRequest {
        FilePanelRequest(kind: .executable, message: message, prompt: "Select Executable")
    }
}
