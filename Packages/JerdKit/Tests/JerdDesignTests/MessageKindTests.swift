import Testing

@testable import JerdDesign

@Suite("Message kind and inline message")
@MainActor
struct MessageKindTests {
    @Test("Every message kind has its own symbol and color")
    func kindsAreDistinct() {
        #expect(Set(MessageKind.allCases.map(\.systemImage)).count == MessageKind.allCases.count)
        #expect(Set(MessageKind.allCases.map(\.color)).count == MessageKind.allCases.count)
    }

    @Test("Error and warning symbols match the status tones with the same meaning")
    func symbolsMatchStatusTones() {
        #expect(MessageKind.error.systemImage == StatusTone.failed.systemImage)
        #expect(MessageKind.warning.systemImage == StatusTone.attention.systemImage)
    }

    @Test("Only warnings and errors are announced when they appear")
    func onlyWarningsAndErrorsAreAnnounced() {
        #expect(MessageKind.allCases.filter(\.isAnnounced) == [.warning, .error])
    }

    @Test("VoiceOver reads the kind before the message text")
    func spokenTextStartsWithKind() {
        let message = InlineMessage("The port is in use.", kind: .error)
        #expect(message.spokenText == "Error: The port is in use.")
    }

    @Test("VoiceOver reads the title between the kind and the text")
    func spokenTextIncludesTitle() {
        let message = InlineMessage("Approve the helper.", kind: .warning, title: "Setup required")
        #expect(message.spokenText == "Warning: Setup required: Approve the helper.")
    }
}
