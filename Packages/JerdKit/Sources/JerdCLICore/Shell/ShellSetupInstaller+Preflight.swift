import Darwin
import Foundation
import JerdFoundation
import JerdRuntimes
import JerdWeb

extension ShellSetupInstaller {
    /// Verifies the default runtime and every runtime that a site pins: the commands can run each one.
    func verifySelectableRuntimes() throws {
        let configuration = try ConfigurationCodec.store(in: layout).load() ?? AppConfiguration()
        guard let defaultID = configuration.defaultRuntimeID,
            configuration.runtimes.contains(where: { $0.id == defaultID })
        else { throw JerdError.unavailable("Select a default PHP runtime in Jerd.") }
        let pinned = Set(
            configuration.sites.compactMap { site -> UUID? in
                if case .pinned(let id) = site.phpSelection { return id }
                return nil
            })
        let verifier = ManagedExecutableVerifier(layout: layout)
        for runtime in configuration.runtimes where runtime.id == defaultID || pinned.contains(runtime.id) {
            do {
                _ = try verifier.verifyPHP(URL(fileURLWithPath: runtime.cliPath))
            } catch let error as JerdError {
                throw JerdError(error.kind, "PHP \(runtime.version): \(error.message)")
            }
        }
    }

    func checkCompanions() throws {
        let missing = JerdError.unavailable("Open Jerd to install Composer and the Laravel installer first.")
        guard let companions = try CLICompanionStore(layout: layout).load() else { throw missing }
        for path in [companions.composerPath, companions.laravelPath] {
            var info = stat()
            guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw missing }
        }
    }

    /// The launcher bytes, after its signature check.
    func readLauncher() throws -> Data {
        let missing = JerdError.unavailable("Build or install a Jerd app with its command launcher first.")
        let descriptor = open(launcher.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw missing }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), info.st_mode & S_IFMT == S_IFREG else { throw missing }
        guard case .success(let data) = DescriptorIO.read(from: descriptor, upTo: Self.launcherLimit + 1),
            data.count <= Self.launcherLimit, !data.isEmpty
        else { throw JerdError.unavailable("Cannot read the command launcher \(launcher.path).") }
        try signatures.checkSignature(of: launcher)
        return data
    }

    /// `bin/` is absent or a private folder, and every entry that the setup replaces is Jerd's.
    func checkBinDirectory() throws {
        var info = stat()
        guard lstat(binDirectory.path, &info) == 0 else { return try requireAbsent(binDirectory) }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else {
            throw JerdError.invalid(
                "The command folder \(binDirectory.path) must be a folder of yours, not a link. It was preserved.")
        }
        try checkLauncherCopy()
        for command in CLICommand.allCases { try checkCommandLink(command.rawValue) }
        for name in [Self.launcherName] + CLICommand.allCases.map(\.rawValue) {
            try StagedFile.checkLeftover(binStage(name))
        }
    }

    private func checkLauncherCopy() throws {
        let copy = binDirectory.appendingPathComponent(Self.launcherName)
        var info = stat()
        guard lstat(copy.path, &info) == 0 else { return try requireAbsent(copy) }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else {
            throw JerdError.invalid(
                "An unrelated \(Self.launcherName) item is in \(binDirectory.path). It was not changed.")
        }
    }

    /// A command name may be absent, Jerd's link to `JerdCLI`, or a legacy link into a runtime folder.
    private func checkCommandLink(_ name: String) throws {
        let link = binDirectory.appendingPathComponent(name)
        var info = stat()
        guard lstat(link.path, &info) == 0 else { return try requireAbsent(link) }
        let unrelated = JerdError.invalid(
            "An unrelated \(name) command already exists in \(binDirectory.path). It was not changed.")
        guard info.st_mode & S_IFMT == S_IFLNK else { throw unrelated }
        if Self.linkDestination(link) == Self.launcherName { return }
        let resolved = link.resolvingSymlinksInPath().pathComponents
        let launcherCopy = binDirectory.appendingPathComponent(Self.launcherName).resolvingSymlinksInPath()
        let legacyRoots = [layout.runtimes.developmentRuntimesDirectory, layout.runtimes.managedRuntimesDirectory]
            .map { $0.resolvingSymlinksInPath().pathComponents }
        guard
            resolved == launcherCopy.pathComponents
                || legacyRoots.contains(where: { resolved.count > $0.count && resolved.starts(with: $0) })
        else { throw unrelated }
    }

    /// The text of a symbolic link, or nil when it cannot be read.
    private static func linkDestination(_ link: URL) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = buffer.withUnsafeMutableBufferPointer { pointer in
            readlink(link.path, pointer.baseAddress, pointer.count - 1)
        }
        guard count >= 0 else { return nil }
        return String(decoding: buffer[..<count], as: UTF8.self)
    }

    private func requireAbsent(_ url: URL) throws {
        guard case .unknown(let code) = FileProbe.presence(at: url) else { return }
        throw JerdError.unavailable("Cannot inspect \(url.path) (\(SystemError.describe(code))).")
    }
}
