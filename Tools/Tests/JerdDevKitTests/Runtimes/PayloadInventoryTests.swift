import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Payload inventory")
struct PayloadInventoryTests {
    private func inventory(_ root: URL) throws -> PayloadInventory {
        PayloadInventory(root: root, catalog: try PayloadFixtures.catalog())
    }

    private func state(_ kind: RuntimeKind, in root: URL) throws -> PayloadInventory.Entry.State {
        let pin = try PayloadFixtures.pin(kind)
        return try inventory(root).entry(for: pin, group: try #require(pin.group)).state
    }

    @Test("A payload that matches its pin and receipt is valid")
    func acceptsValidPayload() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try PayloadFixtures.writePayload(.mailpit, in: root)
        guard case .valid(let payload) = try state(.mailpit, in: root) else {
            Issue.record("Expected a valid payload.")
            return
        }
        #expect(payload.receipt.files.count == 2)
    }

    @Test("A missing folder is missing, not invalid")
    func reportsMissing() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        guard case .missing = try state(.rustfs, in: root) else {
            Issue.record("Expected a missing payload.")
            return
        }
    }

    @Test("Changed, extra, and missing files and a wrong mode make the payload invalid")
    func rejectsChangedFiles() throws {
        let edits: [(URL) throws -> Void] = [
            { try Data("other".utf8).write(to: $0.appending(path: "LICENSE")) },
            { try Data("x".utf8).write(to: $0.appending(path: "extra")) },
            { try FileManager.default.removeItem(at: $0.appending(path: "LICENSE")) },
            { _ = chmod($0.appending(path: "bin/mailpit").path, 0o600) },
            {
                try FileManager.default.createSymbolicLink(
                    at: $0.appending(path: "link"), withDestinationURL: $0.appending(path: "LICENSE"))
            },
        ]
        for edit in edits {
            let root = try TestFixtures.temporaryFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            try edit(try PayloadFixtures.writePayload(.mailpit, in: root))
            guard case .invalid = try state(.mailpit, in: root) else {
                Issue.record("Expected an invalid payload.")
                continue
            }
        }
    }

    @Test("Finder metadata does not make a payload invalid")
    func ignoresFinderMetadata() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try PayloadFixtures.writePayload(.mailpit, in: root)
        try Data("finder".utf8).write(to: folder.appending(path: "bin/.DS_Store"))
        guard case .valid = try state(.mailpit, in: root) else {
            Issue.record("Expected a valid payload.")
            return
        }
    }

    @Test("A receipt of another pin version is refused")
    func rejectsAnotherPin() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try PayloadFixtures.writePayload(.mailpit, in: root)
        let receiptURL = folder.appending(path: PayloadReceipt.fileName)
        let text = try String(contentsOf: receiptURL, encoding: .utf8)
        let pin = try PayloadFixtures.pin(.mailpit)
        try Data(text.replacingOccurrences(of: pin.version, with: "9.9.9").utf8).write(to: receiptURL)
        guard case .invalid(let message) = try state(.mailpit, in: root) else {
            Issue.record("Expected an invalid payload.")
            return
        }
        #expect(message.contains("does not match its pin"))
    }

    @Test("An unreadable catalog is a check failure with its path")
    func reportsUnreadableCatalog() {
        #expect(throws: DevFailure.self) { try PayloadInventory.catalog(at: URL(filePath: "/nonexistent.json")) }
    }
}
