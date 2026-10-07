import JerdDesign
import SwiftUI

/// The one page banner for a missing service runtime. When the bundled setup at launch failed,
/// it shows why, as a warning; else it says that the runtime is not installed. Both lead to
/// Runtimes, so the page names the problem once and with its next step.
struct MissingRuntimeBanner: View {
    /// The words of one service's banner.
    struct Copy {
        /// What to install, for example `Mailpit`.
        let runtime: String
        /// The banner title after a failed setup, for example "Mailpit setup failed".
        let failedTitle: String
        /// Why to install it, for example "to start the inbox".
        let purpose: String
        /// The stable name of the page, for example `mail`.
        let identifier: String
    }

    /// What the banner shows.
    struct Message: Equatable {
        let title: String?
        let text: String
        let kind: MessageKind
        let identifier: String
    }

    let copy: Copy
    let setupFailure: String?
    let showRuntimes: @MainActor () -> Void

    var body: some View {
        let message = Self.message(copy: copy, setupFailure: setupFailure)
        InlineMessage(
            message.text, kind: message.kind, title: message.title, style: .banner,
            action: PageAction("View Runtimes", identifier: "\(copy.identifier).view-runtimes", perform: showRuntimes),
            identifier: message.identifier)
    }

    /// A failed setup is a warning with its reason; a runtime that is only missing is information.
    static func message(copy: Copy, setupFailure: String?) -> Message {
        guard let setupFailure else {
            return Message(
                title: nil, text: "\(copy.runtime) is not installed. Install it in Runtimes \(copy.purpose).",
                kind: .info,
                identifier: "\(copy.identifier).no-runtime")
        }
        return Message(
            title: copy.failedTitle,
            text: "\(sentence(setupFailure)) Install \(copy.runtime) in Runtimes \(copy.purpose).", kind: .warning,
            identifier: "\(copy.identifier).runtime-setup-failed")
    }

    /// The reason as a sentence, so the instruction after it reads as a new sentence.
    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return trimmed }
        return trimmed + "."
    }
}
