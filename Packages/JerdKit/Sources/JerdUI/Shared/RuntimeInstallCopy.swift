import JerdRuntimes

/// The words of a pinned runtime installation that the Databases page and Runtimes share, so both
/// ask the same question with the same facts.
enum RuntimeInstallCopy {
    /// The confirm button of the install dialog.
    static let confirmTitle = "Download and Install"

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
    static func confirmationMessage(_ release: RuntimeRelease) -> String {
        confirmationMessage(
            source: release.artifact.downloadURL?.host ?? "its publisher", downloadSize: release.downloadSize ?? 0,
            requiredSpace: release.requiredSpace, isSigned: release.pinnedSignature != nil)
    }
}
