import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release state and manifest")
struct ReleaseStateTests {
    static func manifest() -> ReleaseManifest {
        ReleaseManifest(
            version: "0.2.0", build: "3", teamID: ReleaseFixtures.team, minimumMacOS: "14.0",
            sourceCommit: ReleaseFixtures.commit, sourceFeedSHA256: String(repeating: "b", count: 64),
            dmg: "Jerd-0.2.0.dmg", symbols: "Jerd-0.2.0-3.dSYMs.zip",
            files: [
                "Jerd-0.2.0.dmg": String(repeating: "c", count: 64),
                "Jerd-0.2.0-3.dSYMs.zip": String(repeating: "d", count: 64),
                "appcast.xml": String(repeating: "e", count: 64), "release-notes.md": String(repeating: "f", count: 64),
            ],
            notarization: .init(app: "app-id", dmg: "dmg-id"), testedSystem: "26.0")
    }

    @Test("The state moves only along the release order and records each change")
    func advancesInOrder() throws {
        var state = ReleaseState(startedAt: Date(timeIntervalSince1970: 0))
        let order: [ReleaseStage] = [
            .prepared, .checked, .draftCreated, .assetsVerified, .releasePublic, .feedProposed, .feedMerged, .published,
        ]
        for (index, stage) in order.enumerated() {
            try state.advance(to: stage, at: Date(timeIntervalSince1970: Double(index + 1)))
        }
        #expect(state.stage == .published && state.stage.isTerminal)
        #expect(state.history.map(\.stage) == [.preparing] + order)
        #expect(throws: DevFailure.self) { try state.advance(to: .checked, at: Date()) }
    }

    @Test("A skipped stage and a move out of a failed preparation are refused")
    func refusesSkips() throws {
        var state = ReleaseState(startedAt: Date())
        #expect(throws: DevFailure.self) { try state.advance(to: .checked, at: Date()) }
        try state.advance(to: .prepareFailed, at: Date())
        #expect(throws: DevFailure.self) { try state.advance(to: .prepared, at: Date()) }
    }

    @Test("The state survives a round trip, and a state with another stage than its history is refused")
    func roundTrip() throws {
        var state = ReleaseState(startedAt: Date(timeIntervalSince1970: 100))
        try state.advance(to: .prepared, at: Date(timeIntervalSince1970: 200))
        state.feedPullRequest = 12
        let decoded = try ReleaseState.decode(state.encoded())
        #expect(decoded == state)
        var object = try #require(try JSONSerialization.jsonObject(with: state.encoded()) as? [String: Any])
        #expect(object["stage"] as? String == "prepared")
        object["stage"] = "checked"
        let mismatch = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DevFailure.self) { try ReleaseState.decode(mismatch) }
        object["history"] = nil
        let broken = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DevFailure.self) { try ReleaseState.decode(broken) }
    }

    @Test("Only a started, unfinished publication protects a candidate")
    func publicationProgress() {
        let protected = ReleaseStage.allCases.filter(\.hasPublicationInProgress)
        #expect(protected == [.draftCreated, .assetsVerified, .releasePublic, .feedProposed, .feedMerged])
    }

    @Test("The manifest round-trips with sorted keys and validates names and digests")
    func manifestRoundTrip() throws {
        let manifest = Self.manifest()
        let data = try manifest.encoded()
        #expect(try ReleaseManifest.decode(data) == manifest)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("}\n"))
        #expect(text.range(of: "\"architecture\"")!.lowerBound < text.range(of: "\"build\"")!.lowerBound)
    }

    @Test("The manifest refuses wrong names, teams, commits, and file sets")
    func manifestRefusals() {
        var changes: [(inout ReleaseManifest) -> Void] = [
            { $0.dmg = "Other.dmg" }, { $0.teamID = "short" }, { $0.sourceCommit = "abc" },
            { $0.files["extra"] = String(repeating: "a", count: 64) }, { $0.repository = "someone/else" },
            { $0.schemaVersion = 2 }, { $0.version = "1" }, { $0.files["appcast.xml"] = "nope" },
        ]
        changes.append { $0.minimumMacOS = "x" }
        for change in changes {
            var manifest = Self.manifest()
            change(&manifest)
            #expect(throws: DevFailure.self) { try manifest.validate() }
        }
    }
}
