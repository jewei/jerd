import JerdDesign
import SwiftUI

/// Gallery page: the five status tones and the service icon tiles.
struct GalleryStatusPage: View {
    var body: some View {
        FormPage {
            PageHeader("Status and icons", subtitle: "Five tones, each with its own color and symbol.")
        } content: {
            Section {
                ForEach(GallerySamples.statuses, id: \.self) { status in
                    LabeledContent(status.tone.rawValue.capitalized) {
                        HStack(spacing: Spacing.medium) {
                            StatusIndicator(status, accessibilityLabel: "Sample status")
                            StatusBadge(status, accessibilityLabel: "Sample status")
                        }
                    }
                }
            } header: {
                Text("Status tones")
            } footer: {
                FormFooter("Busy shows a spinner. With Reduce Motion on, it shows a clock symbol.")
            }
            Section("Service icons") {
                tints
                sizes
            }
        }
    }

    private var tints: some View {
        HStack(spacing: Spacing.medium) {
            ForEach(GallerySamples.tintSymbols, id: \.tint) { sample in
                VStack(spacing: Spacing.tight) {
                    ServiceIcon(systemImage: sample.systemImage, tint: sample.tint)
                    Text(sample.tint.rawValue.capitalized)
                        .textRole(.caption)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Spacing.tight)
    }

    private var sizes: some View {
        HStack(alignment: .bottom, spacing: Spacing.large) {
            ForEach(ServiceIcon.Size.allCases, id: \.self) { size in
                ServiceIcon(systemImage: "globe", tint: .sites, size: size)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.tight)
    }
}
