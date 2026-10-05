import Foundation
import JerdFoundation
import JerdServiceKit

/// Finds, checks, and describes database folders without a registration.
///
/// Rules:
/// - Only a folder with database files (`runtime.json`, `initialized.json`, or `data/`) is
///   retained. An empty or log-only folder of a never-started service is not listed.
/// - A record comes from `removed-registration.json`, or for folders of older builds from
///   `runtime.json` with a registered runtime of the same engine and version.
/// - Data is restorable only with the exact original runtime registration (path included), a
///   matching identity and initialization marker, a real `data/` folder, and valid credentials.
/// - Sizes are computed off the manager actor and can be cancelled.
struct RetainedDatabaseCatalog: Sendable {
    /// The read limit of registration and identity files.
    static let recordLimit = 65_536

    let layout: DatabasesLayout

    /// Every retained folder that is not in `configuration`, sorted by name.
    func list(excluding configuration: DatabaseConfiguration) async throws -> [RetainedDatabase] {
        let parent = layout.instancesDirectory
        guard FileProbe.presence(at: parent).mayExist else { return [] }
        try OwnedDirectory.requireContained(parent, in: layout.root)
        var rows: [RetainedDatabase] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: parent.path) {
            guard let id = UUID(uuidString: name), id.uuidString == name, configuration.service(id) == nil else {
                continue
            }
            let files = DatabaseInstanceFiles(layout: layout.instance(id))
            guard Self.holdsDatabase(files) else { continue }
            rows.append(try await describe(id, files: files, configuration: configuration))
        }
        return rows.sorted { $0.name < $1.name }
    }

    /// True when the folder has any database file. Only such folders are retained.
    static func holdsDatabase(_ files: DatabaseInstanceFiles) -> Bool {
        [files.layout.runtimeIdentityFile, files.layout.initializedMarkerFile, files.data].contains {
            FileProbe.presence(at: $0).mayExist
        }
    }

    private func describe(
        _ id: UUID, files: DatabaseInstanceFiles, configuration: DatabaseConfiguration
    )
        async throws -> RetainedDatabase
    {
        var name = DatabaseMessages.retainedName(id)
        var registration: RemovedRegistration?
        var problem: String?
        do {
            let record = try record(for: id, configuration: configuration)
            registration = record
            name = record.service.name
            try validate(record, configuration: configuration)
        } catch {
            problem = FailureDetail.describe(error)
        }
        var bytes: Int64?
        if problem == nil {
            do {
                bytes = try await DirectorySize.bytes(in: files.root)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                bytes = nil  // A size is optional information. The data stays restorable.
            }
        }
        return RetainedDatabase(
            id: id, name: name, runtime: registration?.runtime, port: registration?.service.port,
            directory: files.root, bytes: bytes, problem: problem)
    }
}
