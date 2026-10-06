import Darwin
import Foundation
import JerdFoundation

extension ShellSetupInstaller {
    /// The current setup state. Reads only; anything that cannot be read counts as not installed.
    public func state() -> CommandLineToolsState {
        guard let copy = Self.readRegularFile(binDirectory.appendingPathComponent(Self.launcherName), followLinks: false),
            CLICommand.allCases.allSatisfy({ hasCommandLink($0.rawValue) }), hasPathBlock()
        else { return .notInstalled }
        // Without a readable launcher in the app, the copy cannot be judged; keep it.
        guard let bundled = Self.readRegularFile(launcher, followLinks: true) else { return .installed }
        return copy == bundled ? .installed : .outdatedLauncher
    }

    /// Replaces an outdated `bin/JerdCLI` with the app's launcher, through the same staged and
    /// signature-checked path as the setup. The app runs it at launch. Shell files do not change.
    /// - Returns: true when the launcher was replaced.
    @discardableResult
    public func refreshLauncherIfInstalled() throws -> Bool {
        guard state() == .outdatedLauncher else { return false }
        let bytes = try readLauncher()
        try checkBinDirectory()
        try copyLauncher(bytes)
        return true
    }

    private func hasCommandLink(_ name: String) -> Bool {
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
        let path = binDirectory.appendingPathComponent(name).path
        let count = buffer.withUnsafeMutableBufferPointer { readlink(path, $0.baseAddress, $0.count - 1) }
        return count >= 0 && buffer[..<count].elementsEqual(Self.launcherName.utf8)
    }

    /// True when a zsh startup file has a well-formed block. A linked file counts here, because
    /// the user can add the block to it by hand.
    private func hasPathBlock() -> Bool {
        Self.shellFileNames.contains { name in
            guard let data = Self.readRegularFile(home.appendingPathComponent(name), followLinks: true) else {
                return false
            }
            if case .present = ShellPathBlockEditor.state(of: [UInt8](data)) { return true }
            return false
        }
    }

    /// The bytes of a regular file within `launcherLimit`, or nil. Never blocks on a FIFO.
    private static func readRegularFile(_ file: URL, followLinks: Bool) -> Data? {
        let descriptor = open(file.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | (followLinks ? 0 : O_NOFOLLOW))
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), info.st_mode & S_IFMT == S_IFREG,
            case .success(let data) = DescriptorIO.read(from: descriptor, upTo: launcherLimit + 1),
            data.count <= launcherLimit
        else { return nil }
        return data
    }
}
