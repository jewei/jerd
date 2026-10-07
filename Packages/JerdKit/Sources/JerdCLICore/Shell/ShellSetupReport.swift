import Foundation

/// The result of a completed shell setup, for the app to show.
public struct ShellSetupReport: Equatable, Sendable {
    /// Jerd's private `bin` folder with `JerdCLI` and the three links.
    public let binDirectory: URL
    /// The startup files that got the PATH block.
    public let changedFiles: [URL]
    /// The startup files that already had the exact PATH block.
    public let unchangedFiles: [URL]
    /// The folder with the original bytes of every changed file that existed. Nil when no
    /// existing file changed.
    public let backupDirectory: URL?

    package init(binDirectory: URL, changedFiles: [URL], unchangedFiles: [URL], backupDirectory: URL?) {
        self.binDirectory = binDirectory
        self.changedFiles = changedFiles
        self.unchangedFiles = unchangedFiles
        self.backupDirectory = backupDirectory
    }

    /// The lines that tell the user what changed and what to do next.
    public var summary: [String] {
        var lines = [
            "php, composer, and laravel now select the registered site's PHP, or the Jerd default outside a site."
        ]
        if let backupDirectory {
            lines.append("Shell backups: \(backupDirectory.path)")
        } else if changedFiles.isEmpty {
            lines.append("The shell files already contain the Jerd PATH block.")
        }
        if !changedFiles.isEmpty {
            lines.append("Run exec zsh -l in an existing terminal to load the PATH change.")
        }
        return lines
    }
}
