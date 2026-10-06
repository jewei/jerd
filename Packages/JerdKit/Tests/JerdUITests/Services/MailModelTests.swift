import JerdMail
import JerdServiceKit
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Mail model")
@MainActor
struct MailModelTests {
    private func launched(_ mail: InMemoryMail) async -> AppFixture {
        let fixture = AppFixture(
            services: InMemoryServicePorts(
                databases: InMemoryDatabases(), storage: InMemoryStorage(), mail: mail))
        await fixture.state.launch()
        return fixture
    }

    private func stoppedMail() -> InMemoryMail {
        InMemoryMail(settings: MailSettings(runtime: SampleServices.mailRuntime), hasData: true)
    }

    @Test("A failed load keeps the file and blocks every change")
    func loadFailure() async {
        let mail = stoppedMail()
        await mail.configure { $0.loadFailure = "settings.json is not valid JSON." }
        let fixture = await launched(mail)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(model.loadState.failureMessage?.hasPrefix(MailModel.loadFailed) == true)
        #expect(!model.canChange)
        #expect(model.start() == nil)
        #expect(model.summary.status.label == "Not loaded")
    }

    @Test("Start runs, then Open Inbox becomes the next step")
    func startThenOpen() async {
        let fixture = await launched(stoppedMail())
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(model.summary.actions.map(\.isPrimary) == [true])
        await model.start()?.value
        #expect(model.state.isRunning)
        #expect(model.summary.actions.map(\.id) == ["mail.stop", "mail.inbox"])
        #expect(model.summary.actions.map(\.isPrimary) == [false, true])
        model.openInbox()
        #expect(fixture.shell.openedURLs == [model.settings.inboxURL])
    }

    @Test("A failed start shows once, as the service state, not as a banner")
    func startFailureShowsOnce() async {
        let mail = stoppedMail()
        await mail.configure { $0.startBehavior = .fail("Mailpit exited before it was ready.") }
        let fixture = await launched(mail)
        defer { fixture.removeDefaults() }
        await fixture.state.mail.start()?.value
        #expect(fixture.state.mail.state == .failed(reason: "Mailpit exited before it was ready."))
        #expect(fixture.state.mail.operation == .idle)
    }

    @Test("A stop that times out leaves the service stuck and offers Stop again")
    func stuckStop() async {
        let mail = InMemoryMail(settings: MailSettings(runtime: SampleServices.mailRuntime), state: .running(pid: 7))
        await mail.configure { $0.stopBehavior = .stuck("Mailpit did not stop.") }
        let fixture = await launched(mail)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        await model.stop()?.value
        #expect(model.state == .stuck(pid: 7, reason: "Mailpit did not stop."))
        #expect(model.operation == .idle)
        #expect(model.canStop)
        #expect(model.status.tone == .attention)
        #expect(!model.canEditPorts)
    }

    @Test("Any other failure shows once as the page banner, until dismissed")
    func otherFailureBanner() async {
        let mail = InMemoryMail(settings: MailSettings(runtime: SampleServices.mailRuntime), state: .running(pid: 7))
        await mail.configure { $0.failure = "The SMTP port did not answer." }
        let fixture = await launched(mail)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        await model.sendTestEmail()?.value
        #expect(model.operation == .failed(message: "The SMTP port did not answer."))
        #expect(model.testResult == nil)
        model.dismissFailure()
        #expect(model.operation == .idle)
    }

    @Test("A test email needs a running inbox and confirms its capture")
    func testEmail() async {
        let fixture = await launched(stoppedMail())
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(model.sendTestEmail() == nil)
        await model.start()?.value
        await model.sendTestEmail()?.value
        #expect(model.testResult == MailModel.testCaptured)
    }

    @Test("Ports change only while stopped; a failure stays in the sheet")
    func ports() async {
        let mail = stoppedMail()
        let fixture = await launched(mail)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        model.editPorts()
        #expect(model.portsDraft == PortsDraft(first: 1025, second: 8025))
        await model.suggestPorts()?.value
        #expect(model.portsDraft == PortsDraft(first: 1026, second: 8026))
        model.portsDraft?.second = "1026"
        #expect(model.savePorts() == nil)
        model.portsDraft?.second = "8030"
        await mail.configure { $0.failure = "Port 8030 is in use." }
        await model.savePorts()?.value
        #expect(model.portsOperation == .failed(message: "Port 8030 is in use."))
        #expect(model.portsDraft != nil)
        await mail.configure { $0.failure = nil }
        await model.savePorts()?.value
        #expect(model.portsDraft == nil)
        #expect(model.settings.ports == MailPorts(smtp: 1026, web: 8030))
    }

    @Test("Copies go through the window clipboard with their confirmation")
    func copies() async {
        let fixture = await launched(stoppedMail())
        defer { fixture.removeDefaults() }
        fixture.state.mail.copyEnvironment()
        #expect(fixture.shell.pasteboard.last?.contains("MAIL_PORT=1025") == true)
        #expect(fixture.state.clipboard.feedback?.text == "Copied Laravel settings")
    }

    @Test("Quit stops the inbox; a stuck stop keeps Jerd open, and resume enables actions")
    func shutdown() async {
        let mail = InMemoryMail(settings: MailSettings(runtime: SampleServices.mailRuntime), state: .running(pid: 7))
        await mail.configure { $0.stopBehavior = .stuck("Timed out.") }
        let fixture = await launched(mail)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(await model.shutdown() == false)
        #expect(!model.canChange)
        model.resumeAfterCancelledQuit()
        #expect(model.canStop)
        await mail.configure { $0.stopBehavior = .succeed }
        #expect(await model.shutdown())
        #expect(model.state == .stopped)
    }

    @Test("The menu offers Open Inbox and the lifecycle step")
    func menu() async {
        let fixture = await launched(stoppedMail())
        defer { fixture.removeDefaults() }
        guard case .submenu(let title, let items) = fixture.state.mail.menuItems.first?.kind else {
            Issue.record("Expected a submenu")
            return
        }
        #expect(title == "Mail")
        #expect(items.map(\.title) == ["Open Inbox", "Start Mail"])
    }
}
