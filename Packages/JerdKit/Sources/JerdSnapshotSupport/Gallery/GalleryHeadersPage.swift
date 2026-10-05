import JerdDesign
import SwiftUI

/// Gallery page: page headers in each state, and the stacked layout of a narrow header.
struct GalleryHeadersPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            runningAndBusyHeaders
            problemHeaders
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var runningAndBusyHeaders: some View {
        sample {
            PageHeader(
                "Studio", subtitle: "https://studio.test",
                status: NamedStatus("Site status", DisplayStatus("Ready", tone: .ready)),
                primaryAction: PageAction("Open in Browser", systemImage: "safari", perform: GallerySamples.noAction),
                secondaryActions: [PageAction("Stop", systemImage: "stop.fill", perform: GallerySamples.noAction)])
        }
        sample {
            PageHeader(
                "Runtimes", subtitle: "Manage the tools that power your local environment.",
                primaryAction: PageAction(
                    "Check for Updates", systemImage: "arrow.clockwise", isEnabled: false,
                    perform: GallerySamples.noAction)
            ) {
                BusyIndicator("Checking for runtime updates")
            }
        }
        sample {
            PageHeader(
                "Mail", subtitle: "A local inbox for test email.",
                status: NamedStatus("Mail status", DisplayStatus("Stopping…", tone: .busy)),
                primaryAction: PageAction(
                    "Start", systemImage: "play.fill", isEnabled: false, perform: GallerySamples.noAction))
        }
    }

    /// A failed long title, and a narrow header that moves its actions under the title.
    @ViewBuilder private var problemHeaders: some View {
        sample {
            PageHeader(
                GallerySamples.longTitle, subtitle: GallerySamples.longPath,
                status: NamedStatus("Site status", DisplayStatus("Failed", tone: .failed)),
                primaryAction: PageAction("Start", systemImage: "play.fill", perform: GallerySamples.noAction))
        }
        sample(width: 440) {
            PageHeader(
                "Storage", subtitle: "S3-compatible buckets on this Mac.",
                status: NamedStatus("Storage status", DisplayStatus("Setup required", tone: .attention)),
                primaryAction: PageAction("Start", systemImage: "play.fill", perform: GallerySamples.noAction),
                secondaryActions: [PageAction("Settings…", perform: GallerySamples.noAction)])
        }
    }

    private func sample(width: CGFloat? = nil, @ViewBuilder header: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, Spacing.section + Spacing.small)
                .padding(.vertical, Spacing.extraLarge)
                .frame(width: width, alignment: .leading)
                .background(alignment: .trailing) {
                    if width != nil {
                        Rectangle().fill(.separator).frame(width: 1)
                    }
                }
            Divider()
        }
    }
}
