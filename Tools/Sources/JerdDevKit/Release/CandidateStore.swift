import Foundation
import JerdFoundation

/// Creates candidate folders and is the only reader and writer of their `state.json`.
struct CandidateStore: Sendable {
    let releases: URL

    /// A new private folder `Jerd-<version>-<build>-<random>` with mode 0700. Each attempt gets its own.
    func create(version: ReleaseVersion, build: Int) throws -> CandidateLayout {
        try FileManager.default.createDirectory(at: releases, withIntermediateDirectories: true)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let root = releases.appending(path: "\(CandidateLayout.namePrefix)\(version)-\(build)-\(suffix)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return CandidateLayout(root: root)
    }

    /// The candidate folder that a user names. It must hold a `state.json`.
    static func existing(_ path: String, workingDirectory: URL) throws -> CandidateLayout {
        let url = path.hasPrefix("/") ? URL(filePath: path) : workingDirectory.appending(path: path)
        let layout = CandidateLayout(root: url.standardizedFileURL)
        guard FileManager.default.fileExists(atPath: layout.state.path) else {
            throw DevFailure.usage("\(path) is not a release candidate folder: it has no state.json.")
        }
        return layout
    }

    static func load(_ layout: CandidateLayout) throws -> ReleaseState {
        let data: Data
        do {
            data = try Data(contentsOf: layout.state)
        } catch {
            throw DevFailure.checkFailed("Cannot read \(layout.state.path).")
        }
        return try ReleaseState.decode(data)
    }

    static func save(_ state: ReleaseState, to layout: CandidateLayout) throws {
        try AtomicFile.write(try state.encoded(), to: layout.state, durability: .standard)
    }

    /// The candidates in the releases folder with their state, for `clean`.
    func candidates() throws -> [(layout: CandidateLayout, candidate: CandidateSelection.Candidate)] {
        guard FileManager.default.fileExists(atPath: releases.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: releases.path)
            .filter { $0.hasPrefix(CandidateLayout.namePrefix) }.sorted()
        return names.compactMap { name in
            let root = releases.appending(path: name, directoryHint: .isDirectory)
            guard !FileTree.isSymbolicLink(root), FileProbe.presence(at: root).mayExist else { return nil }
            let layout = CandidateLayout(root: root)
            let state = try? Self.load(layout)
            let created = (try? root.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (layout, .init(name: name, startedAt: state?.startedAt ?? created, stage: state?.stage))
        }
    }
}
