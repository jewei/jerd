import Darwin
import Foundation
import JerdFoundation

extension ShellSetupInstaller {
    /// The mode of the launcher copy: only the user can read and run it.
    static let launcherMode: mode_t = 0o700

    /// Copies the signed launcher to `bin/JerdCLI` and points the three command links to it.
    ///
    /// The copy is checked again after the write, so `bin/JerdCLI` is always a complete, signed file.
    /// Each link is staged under its fixed name and renamed over the old entry.
    func installLauncher(_ bytes: Data) throws {
        try OwnedDirectory.create(binDirectory, within: layout.root)
        let stage = binStage(Self.launcherName)
        try StagedFile.removeLeftover(stage)
        try StagedFile.write(bytes, to: stage, mode: Self.launcherMode)
        do {
            try signatures.checkSignature(of: stage)
        } catch {
            try StagedFile.removeLeftover(stage)
            throw error
        }
        try StagedFile.commit(stage, to: binDirectory.appendingPathComponent(Self.launcherName))
        for command in CLICommand.allCases {
            let link = binStage(command.rawValue)
            try StagedFile.removeLeftover(link)
            try StagedFile.link(link, to: Self.launcherName)
            try StagedFile.commit(link, to: binDirectory.appendingPathComponent(command.rawValue))
        }
    }
}
