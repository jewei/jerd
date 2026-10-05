import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct InstallationIdentityTests {
    @Test func anAbsentIdentityReadsAsNilAndIsCreatedOnce() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let identity = InstallationIdentity(environment: DataLayout(root: folder.url).environment)
        #expect(try identity.read() == nil)
        let created = try identity.readOrCreate()
        #expect(text(identity.file) == created.uuidString)
        #expect(mode(identity.file) == 0o600)
        #expect(try identity.readOrCreate() == created)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: identity.file.deletingLastPathComponent().path)
                == ["installation-id"])
    }

    @Test(arguments: ["not-a-uuid", "\(UUID().uuidString)\n", " \(UUID().uuidString)", ""])
    func anInvalidIdentityIsCorruptAndPreserved(_ content: String) throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let identity = InstallationIdentity(environment: DataLayout(root: folder.url).environment)
        try OwnedDirectory.create(identity.file.deletingLastPathComponent())
        try AtomicFile.write(Data(content.utf8), to: identity.file)
        let corrupt = JerdError.corrupt("The installation identity is invalid. It was preserved.")
        #expect(throws: corrupt) { try identity.read() }
        #expect(throws: corrupt) { try identity.readOrCreate() }
        #expect(text(identity.file) == content)
    }

    @Test func aLowercaseUUIDIsAccepted() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let identity = InstallationIdentity(environment: DataLayout(root: folder.url).environment)
        let id = UUID()
        try OwnedDirectory.create(identity.file.deletingLastPathComponent())
        try AtomicFile.write(Data(id.uuidString.lowercased().utf8), to: identity.file)
        #expect(try identity.read() == id)
    }

    @Test func aLinkedIdentityFileIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let identity = InstallationIdentity(environment: DataLayout(root: folder.url).environment)
        let target = try folder.file("elsewhere", UUID().uuidString)
        try OwnedDirectory.create(identity.file.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: identity.file, withDestinationURL: target)
        #expect(throws: JerdError.self) { try identity.readOrCreate() }
    }

    @Test func concurrentCreationAgreesOnOneIdentity() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let identity = InstallationIdentity(environment: DataLayout(root: folder.url).environment)
        let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
            for _ in 0..<8 { group.addTask { try identity.readOrCreate() } }
            return try await group.reduce(into: Set<UUID>()) { $0.insert($1) }
        }
        #expect(ids.count == 1)
        #expect(try identity.read() == ids.first)
    }
}
