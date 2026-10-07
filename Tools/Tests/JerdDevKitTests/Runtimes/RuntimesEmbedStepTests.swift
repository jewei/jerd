import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

/// Runs the embed step with the real `rsync` on temporary folders.
@Suite("Runtime payload embedding")
struct RuntimesEmbedStepTests {
    private struct Setup {
        let repository: Repository
        let output: RecordingTextOutput
        var context: DevContext {
            TestFixtures.context(
                repository: repository,
                runner: ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups()), output: output)
        }
        var destination: URL { repository.path("products/Jerd.app/Contents/Resources/RuntimePayloads") }

        func embed(requiresAll: Bool) async throws {
            try await RuntimesEmbedStep.run(context, destination: destination, requiresAll: requiresAll)
        }
    }

    private func setup() throws -> Setup {
        Setup(repository: try PayloadFixtures.repository(), output: RecordingTextOutput())
    }

    @Test("Copies every verified payload and the catalog, and removes folders that no pin names")
    func embedsVerifiedPayloads() async throws {
        let setup = try setup()
        defer { try? FileManager.default.removeItem(at: setup.repository.root) }
        try PayloadFixtures.writePayloads(in: setup.repository.payloads)
        try TestFixtures.write(
            "old", to: "products/Jerd.app/Contents/Resources/RuntimePayloads/mail/old-1/x",
            in: setup.repository.root)
        try TestFixtures.write(
            "old", to: "products/Jerd.app/Contents/Resources/RuntimePayloads/DevelopmentRuntimes/x",
            in: setup.repository.root)
        try await setup.embed(requiresAll: true)
        let mail = try PayloadFixtures.pin(.mailpit).id
        let names = try FileManager.default.contentsOfDirectory(atPath: setup.destination.path).sorted()
        #expect(names == ["database", "development", "mail", "runtimes.json", "storage"])
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: setup.destination.appending(path: "mail").path) == [
                mail
            ])
        let embedded = setup.destination.appending(path: "mail/\(mail)/bin/mailpit")
        #expect(try Data(contentsOf: embedded) == Data("binary".utf8))
        let catalog = try Data(contentsOf: setup.destination.appending(path: "runtimes.json"))
        #expect(catalog == (try Data(contentsOf: setup.repository.runtimeCatalog)))
    }

    @Test("Release refuses a missing payload; Debug embeds the rest with a warning")
    func missingPayloads() async throws {
        let setup = try setup()
        defer { try? FileManager.default.removeItem(at: setup.repository.root) }
        try PayloadFixtures.writePayloads([.mail], in: setup.repository.payloads)
        await #expect(throws: DevFailure.self) { try await setup.embed(requiresAll: true) }
        #expect(!FileManager.default.fileExists(atPath: setup.destination.path))
        try await setup.embed(requiresAll: false)
        #expect(setup.output.all.contains("warning: The app builds without these payloads:"))
        #expect(FileManager.default.fileExists(atPath: setup.destination.appending(path: "mail").path))
    }

    @Test("A changed payload fails the build before anything is copied")
    func changedPayloadFails() async throws {
        let setup = try setup()
        defer { try? FileManager.default.removeItem(at: setup.repository.root) }
        let folder = try PayloadFixtures.writePayload(.mailpit, in: setup.repository.payloads)
        try Data("changed".utf8).write(to: folder.appending(path: "LICENSE"))
        await #expect(throws: DevFailure.self) { try await setup.embed(requiresAll: false) }
        #expect(!FileManager.default.fileExists(atPath: setup.destination.path))
        #expect(setup.output.all.contains("Files changed: LICENSE"))
    }

    @Test("Without payloads, Debug removes earlier embedded payloads")
    func noPayloadsRemovesDestination() async throws {
        let setup = try setup()
        defer { try? FileManager.default.removeItem(at: setup.repository.root) }
        try TestFixtures.write(
            "old", to: "products/Jerd.app/Contents/Resources/RuntimePayloads/x",
            in: setup.repository.root)
        try await setup.embed(requiresAll: false)
        #expect(!FileManager.default.fileExists(atPath: setup.destination.path))
    }

    @Test("Refuses a destination outside an app payload folder")
    func refusesOtherDestinations() async throws {
        let setup = try setup()
        defer { try? FileManager.default.removeItem(at: setup.repository.root) }
        await #expect(throws: DevFailure.self) {
            try await RuntimesEmbedStep.run(setup.context, destination: setup.repository.root, requiresAll: false)
        }
    }

    @Test("The copy keeps unchanged files and never copies Finder metadata")
    func syncPlan() {
        let invocation = PayloadSyncPlan.copy(URL(filePath: "/p/mail/m"), to: URL(filePath: "/a/mail/m"))
        #expect(invocation.executable.path == "/usr/bin/rsync")
        #expect(invocation.arguments == ["-a", "--delete", "--exclude=.DS_Store", "/p/mail/m/", "/a/mail/m/"])
    }

    @Test("Only the catalog and the pinned folders stay")
    func extraneousPaths() {
        let paths = PayloadSyncPlan.extraneous(
            existing: ["runtimes.json": [], "mail": ["m-1", "m-0"], "MailRuntime": ["x"], "notes": []],
            expected: ["mail": ["m-1"]], catalogName: "runtimes.json")
        #expect(paths == ["MailRuntime", "mail/m-0", "notes"])
    }
}
