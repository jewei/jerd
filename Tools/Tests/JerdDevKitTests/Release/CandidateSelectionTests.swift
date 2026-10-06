import Foundation
import Testing

@testable import JerdDevKit

@Suite("Candidate clean selection")
struct CandidateSelectionTests {
    static func candidate(_ name: String, _ day: Double, _ stage: ReleaseStage?) -> CandidateSelection.Candidate {
        .init(name: name, startedAt: Date(timeIntervalSince1970: day * 86_400), stage: stage)
    }

    @Test("Keeps the newest candidates and removes finished or unstarted older ones")
    func keepsNewest() {
        let candidates = [
            Self.candidate("a", 1, .published), Self.candidate("b", 2, .prepareFailed),
            Self.candidate("c", 3, .prepared),
            Self.candidate("d", 4, .checked), Self.candidate("e", 5, .published),
        ]
        let result = CandidateSelection.select(candidates, keep: 2)
        #expect(result.remove == ["c", "b", "a"])
        #expect(result.protected.isEmpty)
    }

    @Test("Never removes a started publication, a running preparation, or an unreadable state")
    func protects() {
        let candidates = [
            Self.candidate("new", 9, .published), Self.candidate("draft", 1, .draftCreated),
            Self.candidate("merged", 2, .feedMerged), Self.candidate("busy", 3, .preparing),
            Self.candidate("old-tool", 4, nil),
        ]
        let result = CandidateSelection.select(candidates, keep: 1)
        #expect(result.remove.isEmpty)
        #expect(Set(result.protected.map(\.name)) == ["draft", "merged", "busy", "old-tool"])
    }

    @Test("Keep zero removes every removable candidate")
    func keepZero() {
        #expect(CandidateSelection.select([Self.candidate("a", 1, .published)], keep: 0).remove == ["a"])
    }
}
