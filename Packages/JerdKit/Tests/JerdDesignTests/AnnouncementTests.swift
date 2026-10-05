import SwiftUI
import Testing

@testable import JerdDesign

@Suite("VoiceOver announcements")
@MainActor
struct AnnouncementTests {
    @Test("A banner error is announced when it appears and again when its text changes")
    func bannerErrorIsAnnouncedOnChange() async {
        let recorder = RecordingAnnouncer()
        let model = MessageModel(text: "The port 5432 is in use.")
        let host = ViewHost(
            MessageView(model: model, style: .banner).environment(\.messageAnnouncer, recorder.announcer))
        defer { host.close() }
        await host.settle()
        model.text = "PostgreSQL could not start."
        await host.settle()
        #expect(recorder.announcements == ["Error: The port 5432 is in use.", "Error: PostgreSQL could not start."])
    }

    @Test("A row error, such as sheet validation, is announced")
    func rowErrorIsAnnounced() async {
        let recorder = RecordingAnnouncer()
        let model = MessageModel(text: "The address studio.test is already in use.")
        let host = ViewHost(MessageView(model: model, style: .row).environment(\.messageAnnouncer, recorder.announcer))
        defer { host.close() }
        await host.settle()
        #expect(recorder.announcements == ["Error: The address studio.test is already in use."])
    }

    @Test("Information and success messages are not announced")
    func calmMessagesAreSilent() async {
        let recorder = RecordingAnnouncer()
        let host = ViewHost(
            VStack {
                InlineMessage("Updated.", kind: .success, style: .banner)
                InlineMessage("Managed by Jerd.", kind: .info)
            }
            .environment(\.messageAnnouncer, recorder.announcer))
        defer { host.close() }
        await host.settle()
        #expect(recorder.announcements.isEmpty)
    }

    @Test("A retained page that is set to silent speaks nothing, even when its error changes")
    func silentAnnouncer() async {
        let recorder = RecordingAnnouncer()
        let model = MessageModel(text: "Failed.")
        let page = MessageView(model: model, style: .banner).environment(\.messageAnnouncer, .silent)
        let host = ViewHost(page.environment(\.messageAnnouncer, recorder.announcer))
        defer { host.close() }
        await host.settle()
        model.text = "Failed again."
        await host.settle()
        #expect(recorder.announcements.isEmpty)
    }

    @Test("Copying the same value twice announces it twice")
    func repeatedCopyIsAnnouncedAgain() async {
        let recorder = RecordingAnnouncer()
        let model = CopyModel()
        let host = ViewHost(CopyView(model: model).environment(\.messageAnnouncer, recorder.announcer))
        defer { host.close() }
        await host.settle()
        model.message = CopyFeedbackMessage("Copied inbox URL")
        await host.settle()
        model.message = CopyFeedbackMessage("Copied inbox URL")
        await host.settle()
        #expect(recorder.announcements == ["Copied inbox URL", "Copied inbox URL"])
    }

    @Test("Two copy messages with the same text are different events")
    func copyMessagesAreEvents() {
        #expect(CopyFeedbackMessage("Copied") != CopyFeedbackMessage("Copied"))
    }
}

@MainActor
@Observable
private final class MessageModel {
    var text: String

    init(text: String) {
        self.text = text
    }
}

private struct MessageView: View {
    let model: MessageModel
    let style: InlineMessage.Style

    var body: some View {
        InlineMessage(model.text, kind: .error, style: style)
    }
}

@MainActor
@Observable
private final class CopyModel {
    var message: CopyFeedbackMessage?
}

private struct CopyView: View {
    @Bindable var model: CopyModel

    var body: some View {
        Color.clear.copyFeedback($model.message)
    }
}
