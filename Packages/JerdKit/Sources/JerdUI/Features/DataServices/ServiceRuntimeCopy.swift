import JerdRuntimes

/// The words of the on-demand runtime installation of a service page: RustFS for Storage and
/// Mailpit for Mail. Both pages use the same sentences with their own names, so tests can pin
/// them. The question and its facts are the shared ones of `RuntimeInstallCopy`.
struct ServiceRuntimeCopy: Equatable {
    /// The runtime, for example `RustFS`.
    let runtime: String
    /// The service as a sentence names it, for example `storage`.
    let service: String

    static let storage = ServiceRuntimeCopy(runtime: "RustFS", service: "storage")
    static let mail = ServiceRuntimeCopy(runtime: "Mailpit", service: "mail")

    /// The status of a service without its runtime.
    static let notInstalledStatus = "Not installed"

    /// The action of the service page that installs the runtime without a start.
    var installTitle: String { "Install \(runtime)…" }

    var cancelled: String { "The \(runtime) installation was cancelled. Nothing was installed." }

    /// Why the page shows no address and no ports before the runtime is installed.
    var portsNotChosen: String { "Jerd chooses two free ports on this Mac when it installs \(runtime)." }

    /// The banner title of a failed installation.
    var failedTitle: String { "\(runtime) was not installed" }

    /// The footer of the Runtime section: what Install and Start do.
    func footer(reuses: Bool) -> String {
        let needs = "\(service.prefix(1).uppercased())\(service.dropFirst()) needs \(runtime)."
        return reuses
            ? "\(needs) Jerd uses the copy that is already on this Mac. Nothing is downloaded."
            : "\(needs) Jerd downloads it only when you install it or start \(service)."
    }

    /// `Install RustFS 1.0.0?`
    func confirmationTitle(_ request: ServiceRuntimeRequest) -> String {
        RuntimeInstallCopy.confirmationTitle(request.offer.title)
    }

    /// The confirm button: the shared words, or the start in the same flow for Start.
    func confirmTitle(_ request: ServiceRuntimeRequest) -> String {
        guard request.startsService else {
            return RuntimeInstallCopy.confirmTitle(reuses: request.offer.reusesInstalledCopy)
        }
        return request.offer.reusesInstalledCopy ? "Install and Start" : "Download and Start"
    }

    /// What the download is, where it comes from, how Jerd checks it, the disk space it needs, and,
    /// for Start, that the service starts next. It never names data: the install does not touch it.
    func confirmationMessage(_ request: ServiceRuntimeRequest) -> String {
        let offer = request.offer
        let facts =
            offer.reusesInstalledCopy
            ? RuntimeInstallCopy.reuseMessage(offer.title)
            : RuntimeInstallCopy.confirmationMessage(
                source: offer.source, downloadSize: offer.downloadSize, requiredSpace: offer.requiredSpace,
                isSigned: false)
        return request.startsService ? "\(facts) Then Jerd starts \(service)." : facts
    }

    /// The row detail of the runtime while it is not installed.
    func notInstalledDetail(_ offer: ServiceRuntimeOffer) -> String {
        offer.reusesInstalledCopy
            ? "Not in use. \(offer.versionLabel) is already on this Mac."
            : "Not installed. \(offer.versionLabel), \(offer.sizeText) download."
    }

    /// The card text while the runtime is not installed, and why Start asks first.
    func cardNotice(_ offer: ServiceRuntimeOffer) -> String {
        offer.reusesInstalledCopy
            ? "\(runtime) is not in use yet. Start uses the copy on this Mac."
            : "\(runtime) is not installed. Start downloads it (\(offer.sizeText))."
    }
}
