import Foundation
import JerdFoundation

/// Installs the `php`, `composer`, and `laravel` commands for zsh. The app runs it on request.
///
/// Order:
/// 1. Preflight, without a write: every PHP runtime that a command can select is a verified
///    managed build; the Composer and Laravel tools exist; the launcher in the app has a valid
///    signature; nothing unrelated is at the command names; every startup file is a regular,
///    private UTF-8 file with a well-formed block or none.
/// 2. Leftovers of a crashed earlier run are removed (only files and links with the fixed stage names).
/// 3. The signed launcher is copied to `bin/JerdCLI`; `bin/php`, `bin/composer`, and `bin/laravel`
///    become relative links to it.
/// 4. The original bytes of each startup file that changes go to `shell-backups/<time>/`.
/// 5. Each startup file is replaced atomically, with its mode. A failure restores the files that
///    were already replaced.
///
/// Startup files: the existing ones of `.zprofile` and `.zshrc`; `.zshrc` when neither exists.
/// A symbolic link or hard link is never replaced: the setup stops and the user adds the block.
public actor ShellSetupInstaller {
    /// The zsh startup files that can get the PATH block, in the order of the edits.
    public static let shellFileNames = [".zprofile", ".zshrc"]
    /// The startup file that the setup creates when none exists.
    public static let newShellFileName = ".zshrc"
    /// The launcher file name in the app bundle and in `bin/`.
    public static let launcherName = "JerdCLI"
    static let shellFileLimit = 1_048_576
    static let launcherLimit = 64 * 1_048_576

    let layout: DataLayout
    let home: URL
    let launcher: URL
    let signatures: any LauncherSignatureChecking
    let now: @Sendable () -> Date
    let timeZone: TimeZone

    /// - Parameters:
    ///   - home: the user's home folder with the zsh startup files.
    ///   - launcher: the signed `JerdCLI` in the app bundle.
    public init(
        layout: DataLayout, home: URL, launcher: URL,
        signatures: any LauncherSignatureChecking = CodeSignatureCheck(),
        now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current
    ) {
        self.layout = layout
        self.home = home.standardizedFileURL
        self.launcher = launcher
        self.signatures = signatures
        self.now = now
        self.timeZone = timeZone
    }

    /// The installer of the current user for the app at `appBundle`.
    public static func live(appBundle: URL) -> ShellSetupInstaller {
        ShellSetupInstaller(
            layout: .currentUser(), home: FileManager.default.homeDirectoryForCurrentUser,
            launcher: appBundle.appendingPathComponent("Contents/MacOS/\(launcherName)"))
    }

    /// Runs the setup. Nothing changes when a preflight check fails.
    public func install() throws -> ShellSetupReport {
        try verifySelectableRuntimes()
        try checkCompanions()
        let launcherBytes = try readLauncher()
        try checkBinDirectory()
        let changes = try planShellFiles()
        try installLauncher(launcherBytes)
        let pending = changes.filter(\.changesFile)
        let backup = try backUp(pending)
        try replace(pending, backup: backup)
        return ShellSetupReport(
            binDirectory: layout.binDirectory, changedFiles: pending.map(\.file),
            unchangedFiles: changes.filter { !$0.changesFile }.map(\.file), backupDirectory: backup)
    }

    var binDirectory: URL { layout.binDirectory }

    /// The fixed stage of an entry in `bin/`: `.<name>-next`.
    func binStage(_ name: String) -> URL { binDirectory.appendingPathComponent(".\(name)-next") }
}
