import JerdDesign
import SwiftUI

/// A label above a complete technical value that wraps and never truncates. The approval
/// shows hostnames and the CA fingerprint in full, because the user compares them.
struct ApprovalValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(label)
            Text(value)
                .font(TextRole.code.font)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
