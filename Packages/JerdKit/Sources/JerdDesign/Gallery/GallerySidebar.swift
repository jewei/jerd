import SwiftUI

/// The sidebar of the gallery workspace: rows in each state and the standard footer.
struct GallerySidebar: View {
    @Binding var selection: String?
    let isEmpty: Bool

    var body: some View {
        List(selection: $selection) {
            if !isEmpty {
                Section("Your Projects") {
                    SidebarRow("Studio", subtitle: "studio.test", status: DisplayStatus("Ready", tone: .ready))
                        .tag("Studio")
                    SidebarRow("API", subtitle: "api.test", status: DisplayStatus("Starting…", tone: .busy))
                        .tag("API")
                    SidebarRow(
                        GallerySamples.longTitle, subtitle: "northwind-storefront.test",
                        status: DisplayStatus("Failed", tone: .failed)
                    )
                    .tag("Long")
                    SidebarRow(
                        "Legacy", subtitle: "legacy.test", status: DisplayStatus("Disabled", tone: .idle),
                        isDimmed: true
                    )
                    .tag("Legacy")
                }
                Section("Tunnels") {
                    SidebarRow(
                        "Studio preview", subtitle: "preview.example.com",
                        status: DisplayStatus("Needs attention", tone: .attention)
                    )
                    .tag("Tunnel")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter(addTitle: "Add", caption: isEmpty ? nil : "4 sites · 1 running") {
                Button("Add Site…", systemImage: "globe", action: GallerySamples.noAction)
                Button("Add Cloudflare Tunnel…", systemImage: "network", action: GallerySamples.noAction)
            }
        }
    }
}
