import JerdDesign
import Observation

/// Copies values and keeps the one window-level copy confirmation, so a copy from a page, the
/// sidebar, or a menu always shows its toast in the main window.
@MainActor
@Observable
public final class Clipboard {
    /// The current confirmation. The detail column shows it and clears it after a few seconds.
    public var feedback: CopyFeedbackMessage?
    @ObservationIgnored private let pasteboard: any PasteboardWriting

    public init(pasteboard: any PasteboardWriting) {
        self.pasteboard = pasteboard
    }

    /// Writes `text` and shows `confirmation`, for example "Copied inbox URL".
    public func copy(_ text: String, confirmation: String) {
        pasteboard.write(text)
        feedback = CopyFeedbackMessage(confirmation)
    }
}
