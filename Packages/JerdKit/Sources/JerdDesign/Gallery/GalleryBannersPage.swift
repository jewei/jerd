import SwiftUI

/// Gallery page: page banners of each kind, the operation banner, and the copy toast.
struct GalleryBannersPage: View {
    var body: some View {
        PageScaffold {
            PageHeader("Banners", subtitle: "Page messages stay visible above the scrolling content.")
        } messages: {
            InlineMessage(
                "A tunnel could not stop safely. Jerd will remain open. Retry Stop in Sites.", kind: .error,
                style: .banner, action: PageAction("Show Tunnel", perform: GallerySamples.noAction),
                dismiss: GallerySamples.noAction)
            InlineMessage(
                "Approve the helper in System Settings to finish HTTPS setup.", kind: .warning, title: "Setup required",
                style: .banner, dismiss: GallerySamples.noAction)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.large) {
                InlineMessage(
                    "An update restarts this service. Jerd keeps a local data backup for recovery.", kind: .info,
                    style: .banner)
                InlineMessage(
                    "Bucket studio-assets is ready.", kind: .success, style: .banner, dismiss: GallerySamples.noAction)
                VStack(spacing: 0) {
                    OperationBanner(
                        "Stopping databases safely…",
                        stop: PageAction("Stop Sites", role: .destructive, perform: GallerySamples.noAction))
                    OperationBanner("Downloading PHP 8.5.1…", progress: 0.42)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(.separator)
                }
                HStack {
                    Spacer()
                    CopyFeedbackToast(message: "Copied inbox URL")
                    Spacer()
                }
            }
        }
    }
}
