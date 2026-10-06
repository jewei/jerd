import JerdDesign
import SwiftUI

/// The label of a visibility switch: an icon tile, the title, and its detail. VoiceOver reads
/// the title and the detail, so the switch keeps the words that the user sees.
struct VisibilityLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    init(_ title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            ServiceIcon(systemImage: systemImage, tint: .appearance, size: .small)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(title)
                    .textRole(.rowTitle)
                Text(detail)
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
