import SwiftUI

extension View {
    /// Adds the bottom bars of the main window's detail column: the operation banner at the
    /// bottom edge, and the copy toast above it. The toast never covers the banner or the
    /// sidebar. Keep `copyFeedback` state at the window level, so sidebar and menu actions can
    /// set it too.
    /// - Parameter operation: The global operation banner, or nil when no operation runs.
    public func detailColumn(
        copyFeedback message: Binding<CopyFeedbackMessage?>, operation: OperationBanner?,
        copyFeedbackDuration: Duration = .seconds(4)
    ) -> some View {
        // The toast modifies the content inside the banner inset, so its bottom edge is the
        // top of the banner.
        self.copyFeedback(message, duration: copyFeedbackDuration)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let operation {
                    operation
                }
            }
    }
}
