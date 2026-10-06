import JerdDesign
import SwiftUI

/// The first section of a Sites or tunnel sheet: a failure, a broken rule, or why Save is off.
/// It sits above the form, so the user sees it at the sheet's default size without scrolling.
struct SheetTopMessage: View {
    let message: String?
    let kind: MessageKind
    let identifier: String

    var body: some View {
        if let message {
            Section {
                InlineMessage(message, kind: kind, identifier: identifier)
            }
        }
    }
}
