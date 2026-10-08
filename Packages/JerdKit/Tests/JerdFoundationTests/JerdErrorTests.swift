import Foundation
import JerdFoundation
import Testing

@Suite struct JerdErrorTests {
    @Test func everyFactoryKeepsItsKindAndTheExactMessage() {
        let factories: [(JerdError.Kind, (String) -> JerdError)] = [
            (.invalid, JerdError.invalid), (.unavailable, JerdError.unavailable), (.corrupt, JerdError.corrupt),
            (.locked, JerdError.locked), (.timedOut, JerdError.timedOut), (.processFailed, JerdError.processFailed),
            (.approvalInterrupted, JerdError.approvalInterrupted), (.partialChange, JerdError.partialChange),
        ]
        #expect(factories.map(\.0) == JerdError.Kind.allCases)
        for (kind, make) in factories {
            let error = make("Message for \(kind).")
            #expect(error.kind == kind)
            #expect(error.message == "Message for \(kind).")
            #expect(error.localizedDescription == "Message for \(kind).")
        }
    }

    @Test func equalityComparesKindAndMessage() {
        #expect(JerdError.invalid("A") == JerdError(.invalid, "A"))
        #expect(JerdError.invalid("A") != JerdError.corrupt("A"))
        #expect(JerdError.invalid("A") != JerdError.invalid("B"))
    }

    @Test func aRemedyKeepsTheKindAndMessageAndTakesPartInEquality() {
        let plain = JerdError.unavailable("Reconnect the helper.")
        let remedied = plain.with(.reconnectHelper)
        #expect(plain.remedy == nil)
        #expect(remedied.remedy == .reconnectHelper)
        #expect(remedied.kind == .unavailable && remedied.message == plain.message)
        #expect(remedied.localizedDescription == "Reconnect the helper.")
        #expect(remedied != plain)
        #expect(remedied.with(.openLoginItems).remedy == .openLoginItems)
    }

    @Test func systemErrorTextNamesTheCause() {
        #expect(SystemError.describe(ENOENT) == "No such file or directory")
    }
}
