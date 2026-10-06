import AppKit
import JerdDesign
import SwiftUI

/// The top of About: the current icon, the name, the tagline, and the version.
struct AboutHeader: View {
    static let iconSide: CGFloat = 64

    let info: AppInfo
    let icon: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.large) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: Self.iconSide, height: Self.iconSide)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text("Jerd")
                    .textRole(.pageTitle)
                Text("Local PHP development. At home on your Mac.")
                    .textRole(.detail)
                Text("Version \(info.version) · Build \(info.build)")
                    .font(TextRole.caption.font.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, Spacing.hairline)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}
