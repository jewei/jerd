import SwiftUI

/// Speaks short messages to VoiceOver: new warnings and errors, and copy confirmations.
/// Components read it from the environment, so tests can record announcements and a page
/// that is kept alive but not visible can turn them off with `.silent`.
public struct MessageAnnouncer: Sendable {
    private let post: @MainActor @Sendable (String) -> Void

    public init(post: @escaping @MainActor @Sendable (String) -> Void) {
        self.post = post
    }

    /// Posts a VoiceOver announcement. This is the default.
    public static let voiceOver = MessageAnnouncer { text in
        AccessibilityNotification.Announcement(text).post()
    }

    /// Speaks nothing. Use it on retained pages that are not on screen.
    public static let silent = MessageAnnouncer { _ in }

    @MainActor
    public func announce(_ text: String) {
        post(text)
    }
}

extension EnvironmentValues {
    /// The announcer that `InlineMessage` and `copyFeedback(_:)` use.
    @Entry public var messageAnnouncer: MessageAnnouncer = .voiceOver
}
