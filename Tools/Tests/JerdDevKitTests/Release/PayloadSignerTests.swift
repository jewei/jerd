import Foundation
import JerdFoundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Payload signing")
struct PayloadSignerTests {
    /// A workspace with payloads inside a fake exported app, and a runner that acts like codesign.
    static func setUp() throws -> (ReleaseWorkspace, CandidateLayout) {
        let workspace = try ReleaseWorkspace()
        let layout = CandidateLayout(root: workspace.path("candidate"))
        try PayloadFixture.write(to: layout.appPayloads, embeddedOnly: true)
        workspace.runner.on("lipo", ["-archs"], output: "arm64\n")
        workspace.runner.on("codesign", ["-d", "--entitlements"], output: "")
        workspace.runner.on(
            "codesign", ["--force"],
            effect: { invocation in
                let file = URL(filePath: invocation.arguments.last!)
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("signed".utf8))
                try handle.close()
            })
        return (workspace, layout)
    }

    static func signer(_ workspace: ReleaseWorkspace, _ layout: CandidateLayout) throws -> PayloadSigner {
        PayloadSigner(
            shell: try workspace.shell(),
            signing: try SigningIdentity(identity: ReleaseFixtures.identity, team: ReleaseFixtures.team),
            layout: layout)
    }

    @Test("Signs every Mach-O file and records the new digests and the signing record")
    func signsAndRecords() async throws {
        let (workspace, layout) = try Self.setUp()
        defer { workspace.remove() }
        let before = try PayloadSigner.verifiedPayloads(in: layout.appPayloads)
        let reports = try await Self.signer(workspace, layout).run()
        #expect(reports.count == before.count)
        #expect(reports.first { $0.payloadID.hasPrefix("php-") }?.signedFiles == 2)
        let after = try PayloadSigner.verifiedPayloads(in: layout.appPayloads)
        for (old, new) in zip(before, after) {
            #expect(new.receipt.signing?.teamID == ReleaseFixtures.team)
            #expect(new.receipt.signing?.sourceReceiptSHA256 == FileDigest.hexSHA256(of: old.receiptBytes))
            #expect(new.receipt.folderID != old.receipt.folderID)
            #expect(
                new.receipt.fileRecords[RelativePath("LICENSE")!] == old.receipt.fileRecords[RelativePath("LICENSE")!])
        }
        let signatures = workspace.runner.calls("codesign", ["--force"])
        #expect(
            signatures.allSatisfy {
                $0.contains("--identifier") && $0.contains("runtime") && $0.contains("--timestamp")
            })
        #expect(signatures.allSatisfy { $0.contains(ReleaseFixtures.identity) })
    }

    @Test("Only the PHP executables get the JIT entitlements")
    func phpGetsJIT() async throws {
        let (workspace, layout) = try Self.setUp()
        defer { workspace.remove() }
        _ = try await Self.signer(workspace, layout).run()
        let withEntitlements = workspace.runner.calls("codesign", ["--force"]).filter { $0.contains("--entitlements") }
        #expect(withEntitlements.count == 2)
        #expect(withEntitlements.allSatisfy { $0.last!.contains("/development/php-") })
        let plist = try #require(withEntitlements.first?.drop { $0 != "--entitlements" }.dropFirst().first)
        let data = try Data(contentsOf: URL(filePath: plist))
        let entitlements = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool]
        #expect(entitlements == [EntitlementPolicy.allowJIT: true, EntitlementPolicy.allowUnsignedMemory: true])
    }

    @Test("A universal file keeps only its arm64 slice")
    func thinsUniversalFiles() async throws {
        let (workspace, layout) = try Self.setUp()
        defer { workspace.remove() }
        workspace.runner.on(
            "lipo",
            effect: { invocation in
                let arguments = invocation.arguments
                try Data(contentsOf: URL(filePath: arguments[0])).write(to: URL(filePath: arguments[4]))
            })
        workspace.runner.on("lipo", ["-archs"], output: "x86_64 arm64\n")
        _ = try await Self.signer(workspace, layout).run()
        #expect(workspace.runner.calls("lipo").contains { $0.count == 5 && $0[1] == "-thin" && $0[2] == "arm64" })
        #expect(try PayloadSigner.verifiedPayloads(in: layout.appPayloads).count > 0)
    }

    @Test("Refuses a file without arm64 code and an unreviewed entitlement")
    func refuses() async throws {
        let (workspace, layout) = try Self.setUp()
        defer { workspace.remove() }
        workspace.runner.on("lipo", ["-archs"], output: "x86_64\n")
        await #expect(throws: DevFailure.self) { _ = try await Self.signer(workspace, layout).run() }
        let (second, secondLayout) = try Self.setUp()
        defer { second.remove() }
        let debug = try EntitlementPolicy.plist([EntitlementPolicy.getTaskAllow: true])
        second.runner.on("codesign", ["-d", "--entitlements"], output: String(decoding: debug, as: UTF8.self))
        await #expect(throws: DevFailure.self) { _ = try await Self.signer(second, secondLayout).run() }
        #expect(second.runner.calls("codesign", ["--force"]).isEmpty)
    }

    @Test("Signs exactly the pins of the embedded groups")
    func signsEmbeddedPayloads() async throws {
        let (workspace, layout) = try Self.setUp()
        defer { workspace.remove() }
        let catalog = try PayloadInventory.catalog(at: layout.appPayloads.appending(path: RuntimePinCatalog.fileName))
        let expected = EmbeddedPayloads.pins(PayloadInventory(root: layout.appPayloads, catalog: catalog)).map(\.pin.id)
        let reports = try await Self.signer(workspace, layout).run()
        #expect(reports.map(\.payloadID) == expected)
        #expect(!expected.isEmpty)
    }

    @Test("Refuses an app that contains a payload that the release does not embed")
    func refusesOtherPayloads() async throws {
        for extra in ["unknown-group/x/LICENSE", "mail/mailpit-0.0.1-arm64/LICENSE"] {
            let (workspace, layout) = try Self.setUp()
            defer { workspace.remove() }
            let file = layout.appPayloads.appending(path: extra)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: file)
            let error = #expect(throws: DevFailure.self) { try PayloadSigner.verifiedPayloads(in: layout.appPayloads) }
            #expect(error?.message.contains("does not embed") == true)
            await #expect(throws: DevFailure.self) { _ = try await Self.signer(workspace, layout).run() }
            #expect(workspace.runner.calls("codesign", ["--force"]).isEmpty)
        }
    }

    @Test("Refuses a changed payload before any file is signed")
    func refusesChangedPayload() async throws {
        let (workspace, layout) = try Self.setUp()
        defer { workspace.remove() }
        let mail = layout.appPayloads.appending(path: "mail/mailpit-1.31.3-arm64/LICENSE")
        try Data("changed".utf8).write(to: mail)
        await #expect(throws: DevFailure.self) { _ = try await Self.signer(workspace, layout).run() }
        #expect(workspace.runner.calls("codesign", ["--force"]).isEmpty)
    }
}
