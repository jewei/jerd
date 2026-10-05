import Foundation
import JerdFoundation
import JerdServiceKit

extension RetainedDatabaseCatalog {
    /// The saved registration of a retained folder, or one rebuilt from the identity of an older build.
    func record(for id: UUID, configuration: DatabaseConfiguration) throws -> RemovedRegistration {
        let instance = layout.instance(id)
        do {
            try OwnedDirectory.requireContained(instance.root, in: layout.root)
        } catch {
            throw DatabaseMessages.retainedFolderInvalid
        }
        if FileProbe.presence(at: instance.removedRegistrationFile).mayExist {
            let record: RemovedRegistration
            do {
                record = try MarkerFile.read(
                    RemovedRegistration.self, from: instance.removedRegistrationFile, limit: Self.recordLimit)
            } catch {
                throw DatabaseMessages.removedRegistrationInvalid
            }
            guard record.isValid, record.service.id == id else { throw DatabaseMessages.removedRegistrationInvalid }
            return record
        }
        return try legacyRecord(for: id, configuration: configuration)
    }

    /// Older builds kept only `runtime.json`. The name and port are rebuilt.
    private func legacyRecord(for id: UUID, configuration: DatabaseConfiguration) throws -> RemovedRegistration {
        let instance = layout.instance(id)
        let identity = try MarkerFile.read(
            DatabaseIdentity.self, from: instance.runtimeIdentityFile, limit: Self.recordLimit)
        guard identity.serviceID == id,
            let runtime = configuration.runtimes.first(where: { $0.id == identity.runtimeID }),
            runtime.engine == identity.engine, runtime.version == identity.version
        else { throw DatabaseMessages.exactRuntimeUnavailable }
        let service = DatabaseService(
            id: id, name: DatabaseMessages.recoveredName(runtime.engine, id), runtimeID: runtime.id,
            port: runtime.engine.defaultPort)
        return RemovedRegistration(service: service, runtime: runtime)
    }

    /// Requires the exact runtime and, for initialized data, matching markers, a real data folder,
    /// and valid credentials. No file is changed.
    func validate(_ record: RemovedRegistration, configuration: DatabaseConfiguration) throws {
        guard configuration.runtimes.contains(record.runtime) else { throw DatabaseMessages.restoreExactRuntime }
        let files = DatabaseInstanceFiles(layout: layout.instance(record.service.id))
        let marker = files.layout.initializedMarkerFile
        guard FileProbe.presence(at: files.data).mayExist || FileProbe.presence(at: marker).mayExist else { return }
        let expected = DatabaseIdentity(service: record.service, runtime: record.runtime)
        for file in [files.layout.runtimeIdentityFile, marker] {
            // A missing or unreadable marker is a refusal too; nothing is changed or deleted.
            let saved = try? MarkerFile.read(DatabaseIdentity.self, from: file, limit: Self.recordLimit)
            guard saved == expected else { throw DatabaseMessages.retainedIncomplete }
        }
        guard DataFolder.isRealDirectory(files.data) else { throw DatabaseMessages.dataDirectoryInvalid }
        _ = try DatabaseCredentials.read(from: files.layout.credentialsFile)
    }
}
