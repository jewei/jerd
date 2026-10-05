import SwiftUI

/// A short "Copied" confirmation at the bottom of the window. It does not move the content,
/// it is announced to VoiceOver, and it clears itself after `duration`.
/// Apply it once at the window root, so copies from the sidebar, menus, and pages all show it.
struct CopyFeedback: ViewModifier {
    @Binding var message: String?
    let duration: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let message {
                        CopyFeedbackToast(message: message)
                            .padding(.bottom, Spacing.large)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: message)
            }
            .onChange(of: message) { _, newMessage in
                if let newMessage {
                    AccessibilityNotification.Announcement(newMessage).post()
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
    /// Shows `message` as a copy confirmation, then sets it to nil after `duration`.
    public func copyFeedback(_ message: Binding<String?>, duration: Duration = .seconds(4)) -> some View {
        modifier(CopyFeedback(message: message, duration: duration))
    }
}
