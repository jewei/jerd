import JerdDatabases

/// The words of the on-demand runtime installation, as pure functions so tests can pin them.
enum DatabaseRuntimeCopy {
    /// The confirm button of the install dialog.
    static let confirmTitle = "Download and Install"

    /// The action of an engine that has no runtime, for example `Install MySQL…`.
    static func installTitle(_ engine: DatabaseEngine) -> String {
        "Install \(engine.title)…"
    }

    static func confirmationTitle(_ offer: DatabaseRuntimeOffer) -> String {
        "Install \(offer.title)?"
    }

    /// What the download is, where it comes from, and how Jerd checks it.
    static func confirmationMessage(_ offer: DatabaseRuntimeOffer) -> String {
        "Jerd downloads \(offer.sizeText) from \(offer.source) and installs it only when it matches its reviewed "
            + "checksum\(offer.engine == .mysql ? " and the publisher signature" : "")."
    }

    /// The row detail of an engine that Jerd can install.
    static func notInstalledDetail(_ offer: DatabaseRuntimeOffer) -> String {
        "Not installed. \(offer.versionLabel), \(offer.sizeText) download."
    }

    /// The note of the Add sheet when the selected engine is not installed yet.
    static func addNote(_ offer: DatabaseRuntimeOffer) -> String {
        "\(offer.engine.title) is not installed yet. Jerd first downloads \(offer.title) (\(offer.sizeText)) from "
            + "\(offer.source) and checks it, then creates the service."
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
