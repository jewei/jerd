import Foundation
import JerdFoundation
import JerdProcess

/// Lists and deletes the runtime update backups of Mail and Storage for the Advanced page.
///
/// Rules:
/// - Each service is inspected alone. A bad service folder gives one protected problem row and
///   never hides the rows of the other service.
/// - A pending or unreadable journal protects every backup of its service.
/// - A delete holds the service lock, refuses while a journal exists or a saved process may live,
///   and removes only the selected backup folder.
public actor BackupRetentionService {
    static let protectedDetail = "Protected while a runtime update needs recovery."
    static let savedDetail =
        "Saved data and settings from a runtime update. Delete only when you no longer need this copy."
    static let lockMessages = InstanceLock.Messages(
        unavailable: "Cannot lock the service backup.", busy: "Stop this service before deleting a backup.")

    private let dataRoot: URL
    private let locations: [BackupLocation]
    private let startGate: StartGate

    public init(layout: DataLayout, startGate: StartGate = StartGate()) {
        self.init(dataRoot: layout.root, locations: BackupLocation.all(in: layout), startGate: startGate)
    }

    public init(dataRoot: URL, locations: [BackupLocation], startGate: StartGate = StartGate()) {
        self.dataRoot = dataRoot
        self.locations = locations
        self.startGate = startGate
    }

    /// Every backup row, sorted by ID. Sizes are computed off this actor and can be cancelled.
    public func inspect() async -> [RetainedBackup] {
        var rows: [RetainedBackup] = []
        for location in locations where FileProbe.presence(at: location.backupsDirectory).mayExist {
            rows += await inspect(location)
        }
        return rows.sorted { $0.id < $1.id }
    }

    /// Deletes the backup `<service>/<UUID>` and nothing else.
    public func remove(_ id: String) async throws {
        let (location, name) = try parse(id)
        try OwnedDirectory.requireContained(location.root, in: dataRoot)
        let lock = try InstanceLock.acquire(at: location.record.lockFile, messages: Self.lockMessages)
        defer { lock.release() }
        guard !FileProbe.presence(at: location.journalFile).mayExist else {
            throw JerdError.unavailable("Complete runtime recovery before deleting service backups.")
        }
        _ = try startGate.requireStopped(location.record, holding: lock)
        let folder = location.backupsDirectory.appendingPathComponent(name, isDirectory: true)
        try OwnedDirectory.requireContained(folder, in: dataRoot)
        try FileManager.default.removeItem(at: folder)
    }

    private func inspect(_ location: BackupLocation) async -> [RetainedBackup] {
        let names: [String]
        do {
            try OwnedDirectory.requireContained(location.backupsDirectory, in: dataRoot)
            names = try FileManager.default.contentsOfDirectory(atPath: location.backupsDirectory.path)
        } catch {
            return [problemRow(id: location.key, location, location.backupsDirectory, error)]
        }
        let pending = FileProbe.presence(at: location.journalFile).mayExist
        var rows: [RetainedBackup] = []
        for name in names where UUID(uuidString: name) != nil {
            let folder = location.backupsDirectory.appendingPathComponent(name, isDirectory: true)
            let id = "\(location.key)/\(name)"
            do {
                try OwnedDirectory.requireContained(folder, in: dataRoot)
                let bytes = try await DirectorySize.bytes(in: folder)
                let detail = pending ? Self.protectedDetail : Self.savedDetail
                rows.append(
                    RetainedBackup(
                        id: id, service: location.displayName, directory: folder, bytes: bytes, detail: detail,
                        isProtected: pending))
            } catch {
                rows.append(problemRow(id: id, location, folder, error))
            }
        }
        return rows
    }

    private func problemRow(
        id: String, _ location: BackupLocation, _ folder: URL, _ error: any Error
    )
        -> RetainedBackup
    {
        RetainedBackup(
            id: id, service: location.displayName, directory: folder, bytes: nil,
            detail: FailureDetail.describe(error), isProtected: true)
    }

    private func parse(_ id: String) throws -> (BackupLocation, String) {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let location = locations.first(where: { $0.key == parts[0] }),
            UUID(uuidString: parts[1]) != nil
        else { throw JerdError.invalid("The selected backup ID is invalid.") }
        return (location, parts[1])
    }
}
