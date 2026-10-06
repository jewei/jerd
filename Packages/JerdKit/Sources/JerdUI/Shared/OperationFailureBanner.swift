import JerdDesign
import SwiftUI

/// The one presentation of a failed page operation: a dismissible error banner at the top of
/// the page that owns the operation. Shows nothing for other states.
struct OperationFailureBanner: View {
    let operation: OperationState
    let identifier: String
    let dismiss: @MainActor () -> Void

    var body: some View {
        if let message = operation.failureMessage {
            InlineMessage(message, kind: .error, style: .banner, identifier: identifier, dismiss: dismiss)
        }
    }
}
