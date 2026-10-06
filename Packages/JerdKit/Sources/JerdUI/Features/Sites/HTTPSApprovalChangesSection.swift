import SwiftUI

/// What the approval changes on this Mac. The scope of the CA trust is not here: it is the
/// warning at the top of the sheet (`trustWarning`), so it is always visible before Approve.
struct HTTPSApprovalChangesSection: View {
    /// The trust scope. It must be readable at the sheet's default size without scrolling.
    static let trustWarning =
        "macOS will trust the Jerd CA for TLS server certificates on all hostnames, not only the sites below. "
        + "Safari, Brave, and Chrome use this trust."

    var body: some View {
        Section("Changes") {
            Label(
                "Jerd installs its signed helper, maps these hostnames to 127.0.0.1, and adds its local CA to the system keychain.",
                systemImage: "lock.shield")
            Label(
                "Jerd only routes registered .test sites on this Mac. PHP and Caddy run as your user. The helper supplies ports 80 and 443.",
                systemImage: "network")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
