import SwiftUI

/// The one style for explanatory text under a form section. Use it as the section footer.
public struct FormFooter: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .textRole(.detail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PageMetrics.rowInset)
    }
}
