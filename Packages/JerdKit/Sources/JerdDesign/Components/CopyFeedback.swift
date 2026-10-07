import SwiftUI

/// A short "Copied" confirmation at the bottom of the view that it modifies. It does not move
/// the content, it is announced to VoiceOver, and it clears itself after `duration`.
/// Keep the message state at the window level, so the sidebar, menus, and pages can all set it,
/// and draw the toast in the detail column with `detailColumn(copyFeedback:operation:)`.
struct CopyFeedback: ViewModifier {
    @Binding var message: CopyFeedbackMessage?
    let duration: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.messageAnnouncer) private var announcer

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let message {
                        CopyFeedbackToast(message: message.text)
                            .padding(.bottom, Spacing.large)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: message)
            }
            .onChange(of: message, initial: true) { _, newMessage in
                if let newMessage {
                    announcer.announce(newMessage.text)
                }
            }
            .task(id: message) {
                guard message != nil else { return }
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return  // A newer message replaced this one.
                }
                message = nil
            }
    }
}

extension View {
    /// Shows `message` as a copy confirmation at the bottom of this view, then sets it to nil
    /// after `duration`. Prefer `detailColumn(copyFeedback:operation:)` in the main window.
    public func copyFeedback(_ message: Binding<CopyFeedbackMessage?>, duration: Duration = .seconds(4)) -> some View {
        modifier(CopyFeedback(message: message, duration: duration))
    }
}
