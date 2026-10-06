import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct HelperWireErrorTests {
    @Test(arguments: JerdError.Kind.allCases)
    func everyKindCrossesTheWire(kind: JerdError.Kind) {
        let error = JerdError(kind, "The hosts file changed. Retry the setup.")
        #expect(HelperWireError.error(from: HelperWireError.text(for: error)) == error)
    }

    @Test func theCodesNeverChange() {
        #expect(
            HelperWireError.text(for: JerdError.partialChange("Done in part.")) == "Done in part. (JERD-PARTIAL-CHANGE)"
        )
        #expect(HelperWireError.codes.count == JerdError.Kind.allCases.count)
        #expect(Set(HelperWireError.codes.values).count == HelperWireError.codes.count)
    }

    @Test func anOldHelpersPlainTextBecomesUnavailable() {
        let text = "Stop Jerd's environment before changing system setup."
        #expect(HelperWireError.error(from: text) == .unavailable(text))
        #expect(HelperWireError.error(from: "Port (80)") == .unavailable("Port (80)"))
    }

    @Test func anUnknownCodeKeepsTheMessageAndTheSafeKind() {
        #expect(HelperWireError.error(from: "Newer rule. (JERD-NEW-KIND)") == .unavailable("Newer rule."))
        #expect(HelperWireError.error(from: "Text (JERD-not a code)") == .unavailable("Text (JERD-not a code)"))
    }

    @Test func otherErrorsAreSentAsUnavailable() {
        let text = HelperWireError.text(for: CocoaError(.coderReadCorrupt))
        #expect(text.hasSuffix(" (JERD-UNAVAILABLE)"))
        #expect(HelperWireError.error(from: text).kind == .unavailable)
    }
}
