import SwiftUI

/// Gallery page: dashboard summary cards in an adaptive grid.
struct GalleryCardsPage: View {
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: Spacing.large)]

    var body: some View {
        PageScaffold {
            PageHeader("Dashboard", subtitle: "Your local development environment")
        } content: {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.large) {
                SummaryCard(
                    "Sites", systemImage: "globe", tint: .sites, status: DisplayStatus("1 running", tone: .ready),
                    summary: "2 registered · 2 enabled · 1/1 tunnels connected", open: GallerySamples.noAction
                ) {
                    Button("Stop All Sites", action: GallerySamples.noAction)
                }
                SummaryCard(
                    "Databases", systemImage: "cylinder.split.1x2", tint: .databases,
                    status: DisplayStatus("Working…", tone: .busy),
                    summary: "Studio development, Studio cache, Reporting warehouse with a long name",
                    open: GallerySamples.noAction)
                SummaryCard(
                    "Storage", systemImage: "externaldrive.badge.icloud", tint: .storage,
                    status: DisplayStatus("Failed", tone: .failed), summary: "1 bucket · S3 port 9000",
                    open: GallerySamples.noAction
                ) {
                    Button("Start Storage", action: GallerySamples.noAction)
                    Button("Open Console", action: GallerySamples.noAction).disabled(true)
                }
                SummaryCard(
                    "Mail", systemImage: "envelope", tint: .mail, status: DisplayStatus("Stopped", tone: .idle),
                    summary: "SMTP port 1025 · Web port 8025", open: GallerySamples.noAction
                ) {
                    Button("Start Mail", action: GallerySamples.noAction)
                }
            }
        }
    }
}
