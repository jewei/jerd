import SwiftUI

/// What the approval changes on this Mac, including the scope of the CA trust.
struct HTTPSApprovalChangesSection: View {
    var body: some View {
        Section("Changes") {
            Label(
                "Jerd installs its signed helper, maps these hostnames to 127.0.0.1, and adds its local CA to the system keychain.",
                systemImage: "lock.shield")
            Label(
                "macOS will trust this Jerd CA for TLS server certificates, so Safari, Brave, and Chrome can use it. This trust applies to all hostnames, not only the sites listed above.",
                systemImage: "exclamationmark.shield")
            Label(
                "Jerd only routes registered .test sites on this Mac. PHP and Caddy run as your user. The helper supplies ports 80 and 443.",
                systemImage: "network")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
