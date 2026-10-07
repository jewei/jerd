import JerdRuntimes

/// The words of the on-demand RustFS installation, as pure functions so tests can pin them. The
/// question and its facts are the shared ones of `RuntimeInstallCopy`.
enum StorageRuntimeCopy {
    /// The action of the Storage page that installs RustFS without a start.
    static let installTitle = "Install RustFS…"

    static let cancelled = "The RustFS installation was cancelled. Nothing was installed."

    /// The banner title of a failed installation.
    static let failedTitle = "RustFS was not installed"

    /// `Install RustFS 1.0.0?`
    static func confirmationTitle(_ request: StorageRuntimeRequest) -> String {
        RuntimeInstallCopy.confirmationTitle(request.offer.title)
    }

    /// The confirm button: the shared words, or the start in the same flow for Start.
    static func confirmTitle(_ request: StorageRuntimeRequest) -> String {
        guard request.startsStorage else {
            return RuntimeInstallCopy.confirmTitle(reuses: request.offer.reusesInstalledCopy)
        }
        return request.offer.reusesInstalledCopy ? "Install and Start" : "Download and Start"
    }

    /// What the download is, where it comes from, how Jerd checks it, the disk space it needs, and,
    /// for Start, that storage starts next. It never names buckets: the install does not touch them.
    static func confirmationMessage(_ request: StorageRuntimeRequest) -> String {
        let offer = request.offer
        let facts =
            offer.reusesInstalledCopy
            ? RuntimeInstallCopy.reuseMessage(offer.title)
            : RuntimeInstallCopy.confirmationMessage(
                source: offer.source, downloadSize: offer.downloadSize, requiredSpace: offer.requiredSpace,
                isSigned: false)
        return request.startsStorage ? "\(facts) Then Jerd starts storage." : facts
    }

    /// The row detail of RustFS while it is not installed.
    static func notInstalledDetail(_ offer: StorageRuntimeOffer) -> String {
        offer.reusesInstalledCopy
            ? "Not in use. \(offer.title) is already on this Mac."
            : "Not installed. \(offer.title), \(offer.sizeText) download."
    }

    /// The card text while RustFS is not installed, and why Start asks first.
    static func cardNotice(_ offer: StorageRuntimeOffer) -> String {
        offer.reusesInstalledCopy
            ? "RustFS is not in use yet. Start uses the copy on this Mac."
            : "RustFS is not installed. Start downloads it (\(offer.sizeText))."
    }
}
