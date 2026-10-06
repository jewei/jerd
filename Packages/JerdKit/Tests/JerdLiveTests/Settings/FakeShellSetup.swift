import Foundation
import JerdCLICore

@testable import JerdLive

/// A shell setup that reports a set state and a fixed report. It changes no file.
actor FakeShellSetup: ShellSetupInstalling {
    var current: CommandLineToolsState
    private(set) var installs = 0
    private(set) var refreshes = 0

    init(_ state: CommandLineToolsState) {
        current = state
    }

    func state() -> CommandLineToolsState { current }

    func install() -> ShellSetupReport {
        installs += 1
        return ShellSetupReport(
            binDirectory: URL(fileURLWithPath: "/nonexistent/Jerd/bin"),
            changedFiles: [URL(fileURLWithPath: "/nonexistent/home/.zshrc")], unchangedFiles: [], backupDirectory: nil)
    }

    func refreshLauncherIfInstalled() -> Bool {
        refreshes += 1
        return current == .outdatedLauncher
    }
}
