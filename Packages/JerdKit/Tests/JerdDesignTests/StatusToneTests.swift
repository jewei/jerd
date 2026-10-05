import SwiftUI
import Testing

@testable import JerdDesign

@Suite("Status tone")
struct StatusToneTests {
    @Test("Every tone has its own color")
    func colorsAreDistinct() {
        let colors = Set(StatusTone.allCases.map(\.color))
        #expect(colors.count == StatusTone.allCases.count)
    }

    @Test("Every tone has its own symbol, so status never depends on color alone")
    func symbolsAreDistinct() {
        let symbols = Set(StatusTone.allCases.map(\.systemImage))
        #expect(symbols.count == StatusTone.allCases.count)
    }

    @Test("Busy and attention differ in color and symbol")
    func busyAndAttentionDiffer() {
        #expect(StatusTone.busy.color != StatusTone.attention.color)
        #expect(StatusTone.busy.systemImage != StatusTone.attention.systemImage)
    }

    @Test("Each tone uses the expected semantic color and symbol")
    func toneMapping() {
        let expected: [StatusTone: (Color, String)] = [
            .ready: (.green, "checkmark.circle.fill"),
            .busy: (.blue, "clock.fill"),
            .idle: (.gray, "stop.circle"),
            .attention: (.orange, "exclamationmark.triangle.fill"),
            .failed: (.red, "xmark.octagon.fill"),
        ]
        for tone in StatusTone.allCases {
            #expect(tone.color == expected[tone]?.0)
            #expect(tone.systemImage == expected[tone]?.1)
        }
    }

    @Test("Only the busy tone shows a spinner")
    func onlyBusyShowsProgress() {
        #expect(StatusTone.allCases.filter(\.showsProgress) == [.busy])
    }

    @Test(
        "A service tone puts failure before work, and work before the running state",
        arguments: [
            (running: true, busy: true, failed: true, tone: StatusTone.failed),
            (running: false, busy: false, failed: true, tone: .failed),
            (running: true, busy: true, failed: false, tone: .busy),
            (running: false, busy: true, failed: false, tone: .busy),
            (running: true, busy: false, failed: false, tone: .ready),
            (running: false, busy: false, failed: false, tone: .idle),
        ])
    func servicePrecedence(running: Bool, busy: Bool, failed: Bool, tone: StatusTone) {
        #expect(StatusTone.service(running: running, busy: busy, failed: failed) == tone)
    }

    @Test("A status names its subject for VoiceOver")
    func spokenDescriptionNamesSubject() {
        let status = DisplayStatus("Ready", tone: .ready)
        #expect(status.spokenDescription(subject: "Site status") == "Site status, Ready")
        #expect(
            status.spokenDescription(subject: "Environment status") != status.spokenDescription(subject: "Site status"))
    }
}
