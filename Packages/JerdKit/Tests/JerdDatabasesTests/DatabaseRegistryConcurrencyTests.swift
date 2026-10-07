import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

/// Registry changes that run in parallel on one manager. The manager actor is reentrant, so each
/// change must save a registry that includes every change that completed while it waited.
@Suite struct DatabaseRegistryConcurrencyTests {
    /// The expected registry after one round of parallel changes.
    private struct Expected {
        var edited: [DatabaseService] = []
        var added: [DatabaseService] = []
        var removed: UUID?
        var restored: DatabaseService?
    }

    private static let rounds = 10
    private static let width = 8

    @Test func parallelEditsAddsRemovesAndRestoresAreAllSaved() async throws {
        for round in 0..<Self.rounds {
            let harness = try DatabaseHarness()
            let manager = try await harness.loadedManager()
            let base = UInt16(30_000 + round * 100)
            let expected = try await runRound(harness, manager, base: base)
            try await requireRegistry(expected, in: await manager.snapshot().configuration)
            // A new manager reads the same registry from disk.
            let reloaded = harness.manager()
            try await requireRegistry(expected, in: reloaded.load())
        }
    }

    /// Prepares the services, then runs every change of one round in parallel.
    private func runRound(
        _ harness: DatabaseHarness, _ manager: DatabaseManager, base: UInt16
    ) async throws
        -> Expected
    {
        let redis = harness.runtime(.redis).id
        var services: [DatabaseService] = []
        for index in 0..<Self.width {
            services.append(try await manager.add(name: "Edit \(index)", runtimeID: redis, port: base + UInt16(index)))
        }
        let doomed = try await manager.add(name: "Doomed", runtimeID: redis, port: base + 50)
        let retained = try await manager.add(name: "Retained", runtimeID: redis, port: base + 51)
        try await manager.start(retained.id)
        try await manager.stop(retained.id)
        try await manager.remove(retained.id)
        return try await withThrowingTaskGroup(of: Expected.self) { group in
            for (index, service) in services.enumerated() {
                group.addTask {
                    let edited = DatabaseService(
                        id: service.id, name: "Edited \(index)", runtimeID: redis, port: base + 20 + UInt16(index))
                    try await manager.edit(edited)
                    return Expected(edited: [edited])
                }
                group.addTask {
                    let added = try await manager.add(
                        name: "Added \(index)", runtimeID: redis, port: base + 40 + UInt16(index))
                    return Expected(added: [added])
                }
            }
            group.addTask {
                try await manager.remove(doomed.id)
                return Expected(removed: doomed.id)
            }
            group.addTask {
                let restored = try await manager.restoreRegistration(retained.id, name: "Restored", port: base + 60)
                return Expected(restored: restored)
            }
            var total = Expected()
            for try await part in group {
                total.edited += part.edited
                total.added += part.added
                total.removed = total.removed ?? part.removed
                total.restored = total.restored ?? part.restored
            }
            return total
        }
    }

    private func requireRegistry(_ expected: Expected, in configuration: DatabaseConfiguration) async throws {
        for service in expected.edited + expected.added {
            #expect(configuration.service(service.id) == service, "\(service.name) was lost")
        }
        let removed = try #require(expected.removed)
        #expect(configuration.service(removed) == nil, "The removed service came back")
        let restored = try #require(expected.restored)
        #expect(configuration.service(restored.id) == restored, "The restored service was lost")
        #expect(configuration.services.count == expected.edited.count + expected.added.count + 1)
    }
}
