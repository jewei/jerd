import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

@testable import JerdDatabases

@Suite struct DatabaseRegistryTests {
    static let runtime = DatabaseRuntime(id: "mysql-8.4", engine: .mysql, version: "8.4.11", path: "/example/runtime")

    private func configuration(_ services: [DatabaseService]) -> DatabaseConfiguration {
        DatabaseConfiguration(runtimes: [Self.runtime], services: services)
    }

    @Test func savedFilesWithDuplicatesOrBadPortsAreInvalid() throws {
        let first = DatabaseService(name: "First", runtimeID: Self.runtime.id, port: 3_307)
        try configuration([first]).validate()
        let duplicatePort = configuration([
            first, DatabaseService(name: "Second", runtimeID: Self.runtime.id, port: 3_307),
        ])
        #expect(throws: DatabaseMessages.unsupportedSettings) { try duplicatePort.validate() }
        var privileged = first
        privileged.port = 443
        #expect(throws: DatabaseMessages.serviceInvalid) { try configuration([privileged]).validate() }
        let sameName = configuration([first, DatabaseService(name: " First ", runtimeID: Self.runtime.id, port: 3_308)])
        try sameName.validate()
        #expect(throws: DatabaseMessages.duplicateName) { try sameName.validateForSave() }
        var future = configuration([first])
        future.schemaVersion = 2
        #expect(throws: DatabaseMessages.unsupportedSettings) { try future.validate() }
        let missing = DatabaseConfiguration(services: [first])
        #expect(throws: DatabaseMessages.runtimeUnavailable) { try missing.validate() }
    }

    @Test(arguments: ["", "   ", "tab\tname", String(repeating: "n", count: 81)])
    func badServiceNamesAreRefused(_ name: String) {
        #expect(!DatabaseConfiguration.isValidName(name))
    }

    @Test func eightyCharactersAreCountedAfterTrimming() {
        #expect(DatabaseConfiguration.isValidName("  " + String(repeating: "n", count: 80) + "  "))
    }

    @Test(arguments: [
        DatabaseRuntime(id: "../x", engine: .redis, version: "1", path: "/a"),
        DatabaseRuntime(id: "x", engine: .redis, version: "1 2", path: "/a"),
        DatabaseRuntime(id: "x", engine: .redis, version: "1", path: "relative"),
        DatabaseRuntime(id: "x", engine: .redis, version: "1", path: "/a\nb"),
    ])
    func unsafeRuntimeRecordsAreRefused(_ runtime: DatabaseRuntime) {
        #expect(throws: DatabaseMessages.runtimeRecordInvalid) {
            try DatabaseConfiguration(runtimes: [runtime]).validate()
        }
    }

    @Test func aPortOfAnotherServiceIsAPortConflictNotCorruption() throws {
        let first = DatabaseService(name: "First", runtimeID: Self.runtime.id, port: 3_307)
        let second = DatabaseService(name: "Second", runtimeID: Self.runtime.id, port: 3_307)
        #expect(throws: DatabaseMessages.portConflict(3_307, with: "First")) {
            try DatabaseRegistry.adding(second, to: configuration([first]))
        }
        #expect(throws: DatabaseMessages.duplicateName) {
            try DatabaseRegistry.adding(
                DatabaseService(name: "First ", runtimeID: Self.runtime.id, port: 3_308), to: configuration([first]))
        }
    }

    @Test func addAndEditTrimNamesAndKeepTheRuntime() throws {
        let added = try DatabaseRegistry.adding(
            DatabaseService(name: "  Main  ", runtimeID: Self.runtime.id, port: 3_307), to: configuration([]))
        var service = try #require(added.services.first)
        #expect(service.name == "Main")
        service.name = " Renamed "
        service.port = 3_308
        let edited = try DatabaseRegistry.replacing(service, in: added)
        #expect(edited.services.first?.name == "Renamed")
        #expect(edited.services.first?.port == 3_308)
        let moved = DatabaseService(id: service.id, name: "Main", runtimeID: "other", port: 3_307)
        #expect(throws: DatabaseMessages.stopBeforeEditing) { try DatabaseRegistry.replacing(moved, in: added) }
    }

    @Test func aKnownRuntimeIDMustNameTheSameRuntime() throws {
        let registered = try DatabaseRegistry.registering([Self.runtime], in: DatabaseConfiguration())
        #expect(try DatabaseRegistry.registering([Self.runtime], in: registered) == registered)
        let changed = DatabaseRuntime(id: Self.runtime.id, engine: .mysql, version: "8.4.12", path: "/example/runtime")
        #expect(throws: DatabaseMessages.runtimeChanged) { try DatabaseRegistry.registering([changed], in: registered) }
    }

    @Test func theStoreRefusesReassignedServicesAndReplacedRuntimesAndKeepsAPreviousCopy() throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url).databases
        let registry = DatabaseRegistry(layout: layout)
        #expect(try registry.load() == DatabaseConfiguration())
        #expect(!exists(layout.servicesFile))
        let other = DatabaseRuntime(id: "mysql-9", engine: .mysql, version: "9.0.0", path: "/example/other")
        let service = DatabaseService(name: "Main", runtimeID: Self.runtime.id, port: 3_307)
        let saved = DatabaseConfiguration(runtimes: [Self.runtime, other], services: [service])
        try registry.save(saved)
        let bytes = contents(layout.servicesFile)
        var reassigned = saved
        reassigned.services[0] = DatabaseService(id: service.id, name: "Main", runtimeID: other.id, port: 3_307)
        #expect(throws: DatabaseMessages.reassignedRuntime) { try registry.save(reassigned) }
        var replaced = saved
        replaced.runtimes[0] = DatabaseRuntime(id: Self.runtime.id, engine: .mysql, version: "8.4.11", path: "/moved")
        #expect(throws: DatabaseMessages.replacedRuntime) { try registry.save(replaced) }
        #expect(contents(layout.servicesFile) == bytes)
        try registry.save(DatabaseRegistry.removing(service.id, from: saved))
        #expect(contents(layout.previousServicesFile) == bytes)
        #expect(mode(layout.servicesFile) == 0o600)
    }

    @Test(arguments: ["", #"{"schemaVersion":99,"runtimes":[],"services":[]}"#])
    func corruptDatabaseSettingsAreNeverReplaced(_ original: String) throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url).databases
        try write(original, to: layout.servicesFile)
        let registry = DatabaseRegistry(layout: layout)
        #expect { try registry.load() } throws: { error in
            let error = try #require(error as? JerdError)
            return error.kind == .corrupt
                && error.message.hasPrefix("Cannot read database settings. The file was preserved.")
        }
        #expect(throws: (any Error).self) { try registry.save(DatabaseConfiguration()) }
        #expect(text(layout.servicesFile) == original)
    }
}
