import JerdRuntimes

/// The words of a pinned runtime installation that the Databases, Storage, and Mail pages and
/// Runtimes share, so all ask the same question with the same facts.
enum RuntimeInstallCopy {
    /// Why an install waits: the one shared installer runs for another page, for example
    /// `The Databases page is installing MySQL 8.4.11. Installs wait until it finishes.`
    static func waits(for place: String, installing name: String) -> String {
        "\(place) is installing \(name). Installs wait until it finishes."
    }

    /// The confirm button of the install dialog: "Install" when nothing is downloaded.
    static func confirmTitle(reuses: Bool) -> String { reuses ? "Install" : "Download and Install" }

    /// The dialog text when the install reuses a copy on this Mac.
    static func reuseMessage(_ name: String) -> String {
        "\(name) is already on this Mac. Jerd checks its files and uses it. Nothing is downloaded."
    }

    /// `Install MySQL 8.4.11?`
    static func confirmationTitle(_ name: String) -> String { "Install \(name)?" }

    /// What Jerd checks before it installs the download.
    static func checks(isSigned: Bool) -> String {
        isSigned ? "its reviewed checksum and the publisher signature" : "its reviewed checksum"
    }

    /// The size, the source, the checks, and the free disk space that the installation needs.
    static func confirmationMessage(
        source: String, downloadSize: Int64, requiredSpace: Int64?, isSigned: Bool
    ) -> String {
        let space = requiredSpace.map { " It needs about \(ByteText.format($0)) of free disk space." } ?? ""
        return "Jerd downloads \(ByteText.format(downloadSize)) from \(source) and installs it only when it matches "
            + "\(checks(isSigned: isSigned)).\(space)"
    }

    /// The confirmation of a pinned release on the Runtimes page.
    static func confirmationMessage(_ release: RuntimeRelease, reuses: Bool) -> String {
        if reuses { return reuseMessage(release.title) }
        return confirmationMessage(
            source: release.artifact.downloadURL?.host ?? "its publisher", downloadSize: release.downloadSize ?? 0,
            requiredSpace: release.requiredSpace, isSigned: release.pinnedSignature != nil)
    }
}
