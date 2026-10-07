import JerdDatabases
import JerdRuntimes

/// The words of the on-demand runtime installation, as pure functions so tests can pin them.
enum DatabaseRuntimeCopy {
    /// The confirm button of the install dialog.
    static func confirmTitle(_ offer: DatabaseRuntimeOffer) -> String {
        RuntimeInstallCopy.confirmTitle(reuses: offer.reusesInstalledCopy)
    }

    /// The action of an engine that has no runtime, for example `Install MySQL…`.
    static func installTitle(_ engine: DatabaseEngine) -> String {
        "Install \(engine.title)…"
    }

    static func confirmationTitle(_ offer: DatabaseRuntimeOffer) -> String {
        RuntimeInstallCopy.confirmationTitle(offer.title)
    }

    /// What the download is, where it comes from, how Jerd checks it, and the disk space it needs.
    static func confirmationMessage(_ offer: DatabaseRuntimeOffer) -> String {
        if offer.reusesInstalledCopy { return RuntimeInstallCopy.reuseMessage(offer.title) }
        return RuntimeInstallCopy.confirmationMessage(
            source: offer.source, downloadSize: offer.downloadSize, requiredSpace: offer.requiredSpace,
            isSigned: offer.isSigned)
    }

    /// The row detail of an engine that Jerd can install.
    static func notInstalledDetail(_ offer: DatabaseRuntimeOffer) -> String {
        offer.reusesInstalledCopy
            ? "Not in use. \(offer.versionLabel) is already on this Mac."
            : "Not installed. \(offer.versionLabel), \(offer.sizeText) download."
    }

    /// The note of the Add sheet when the selected engine is not installed yet.
    static func addNote(_ offer: DatabaseRuntimeOffer) -> String {
        if offer.reusesInstalledCopy {
            return "\(offer.engine.title) is not in use yet. Jerd first uses the \(offer.title) that is already on "
                + "this Mac, then creates the service. Nothing is downloaded."
        }
        return
            "\(offer.engine.title) is not installed yet. Jerd first downloads \(offer.title) (\(offer.sizeText)) from "
            + "\(offer.source) and checks it, then creates the service. It needs about "
            + "\(ByteText.format(offer.requiredSpace)) of free disk space."
    }

    /// Why Install is off while the Runtimes page installs a runtime.
    static func waitsForRuntimes(_ name: String) -> String {
        "Runtimes is installing \(name). Install again when it finishes."
    }

    /// The confirm button of the Add sheet.
    static func addTitle(installsRuntime: Bool) -> String {
        installsRuntime ? "Install and Create" : "Create and Start"
    }

    static func cancelled(_ offer: DatabaseRuntimeOffer) -> String {
        "The \(offer.engine.title) installation was cancelled. Nothing was installed."
    }

    /// The engine name in the Add sheet picker.
    static func engineLabel(_ engine: DatabaseEngine, isInstalled: Bool) -> String {
        isInstalled ? engine.title : "\(engine.title) (not installed)"
    }
}
