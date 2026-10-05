import JerdDesign
import SwiftUI

/// Gallery page: a full window with toolbar, sidebar, footer, a form page or an empty state,
/// and the operation banner. It proves the components fit together at both window sizes.
struct GalleryWorkspace: View {
    let showsEmptyState: Bool
    @State private var section = "Sites"
    @State private var selection: String? = "Studio"
    /// Window-level copy feedback, as the main window keeps it: the sidebar and menus can set it.
    @State private var copied: CopyFeedbackMessage?

    init(showsEmptyState: Bool) {
        self.showsEmptyState = showsEmptyState
        _copied = State(initialValue: showsEmptyState ? nil : CopyFeedbackMessage("Copied site URL"))
    }

    var body: some View {
        NavigationSplitView {
            GallerySidebar(selection: $selection, isEmpty: showsEmptyState)
                .navigationSplitViewColumnWidth(
                    min: WindowMetrics.sidebarMinimumWidth, ideal: WindowMetrics.sidebarIdealWidth,
                    max: WindowMetrics.sidebarMaximumWidth)
        } detail: {
            Group {
                if showsEmptyState {
                    emptyState
                } else {
                    GallerySitePage()
                }
            }
            .detailColumn(
                copyFeedback: $copied, operation: showsEmptyState ? nil : operation,
                copyFeedbackDuration: .seconds(3600))
        }
        .removingToolbarTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $section) {
                    ForEach(["Dashboard", "Sites", "Databases", "Storage", "Mail"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Runtimes", systemImage: "shippingbox", action: GallerySamples.noAction)
                    .help("Manage runtimes")
            }
        }
    }

    private var emptyState: some View {
        EmptyState(
            "A Home for Your Local Sites", systemImage: "globe.desk",
            message: "Run a local PHP project with HTTPS, or connect an existing Cloudflare tunnel."
        ) {
            Button("Add Your First Site…", systemImage: "plus", action: GallerySamples.noAction)
                .buttonStyle(.borderedProminent)
            Button("Add Cloudflare Tunnel…", action: GallerySamples.noAction)
                .buttonStyle(.link)
        }
    }

    private var operation: OperationBanner {
        OperationBanner(
            "Stopping PHP-FPM and Caddy…",
            stop: PageAction("Stop Sites", role: .destructive, perform: GallerySamples.noAction))
    }
}
