import Foundation
import JerdDesign
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdServiceKit
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Mailpit on demand")
@MainActor
struct MailRuntimeInstallTests {
    /// An app at first launch: no Mailpit yet, and the pinned Mailpit on offer.
    private func launched(
        behavior: InstallBehavior = .succeed, offer: ServiceRuntimeOffer? = SampleServices.mailOffer,
        storage: InMemoryStorage = InMemoryStorage(), runtimes: InMemoryRuntimeInventory? = nil
    ) async -> (AppFixture, InMemoryMail) {
        let mail = InMemoryMail()
        await mail.configure {
            $0.offer = offer
            $0.installBehavior = behavior
        }
        let fixture = AppFixture(
            runtimes: runtimes ?? InMemoryRuntimeInventory(inventory: SampleData.inventory),
            services: InMemoryServicePorts(databases: InMemoryDatabases(), storage: storage, mail: mail))
        await fixture.state.launch()
        return (fixture, mail)
    }

    private static let waiting = InstallBehavior.suspend(
        RuntimeInstallProgress(
            RuntimePipeline.downloadMessage("Mailpit 1.31.3", fraction: 0.4, size: .exact(9_848_192)), 0.4))

    @Test("First launch downloads nothing and offers Mailpit on the page, the card, and the menu bar")
    func firstLaunchOffersMailpit() async throws {
        let (fixture, mail) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(model.runtimeOffer == SampleServices.mailOffer)
        #expect(await mail.calls == ["load"])
        #expect(model.canInstallRuntime && model.canStart && model.startInstallsRuntime)
        let summary = model.summary
        #expect(summary.summary == "Mailpit is not installed. Start downloads it (9.8\u{00A0}MB).")
        #expect(summary.actions.map(\.title) == ["Start"] && summary.actions.allSatisfy(\.isEnabled))
        #expect(summary.actions.first?.spokenTitle == "Start Mail")
        guard case .submenu(_, let items) = try #require(model.menuItems.first).kind else {
            Issue.record("Mail has one submenu")
            return
        }
        let actions = items.compactMap(\.action)
        #expect(actions.map(\.title) == ["Open Inbox", "Start Mail"])
        #expect(actions.map(\.isEnabled) == [false, true])
        #expect(actions.first?.unavailableReason == "Install Mailpit, then start mail to open the inbox.")
    }

    @Test("Before Mailpit is installed: no address to copy, no port edit, no test email, status Not installed")
    func beforeInstallNoPorts() async {
        let (fixture, _) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        let before = MailConnectionSection.values(model)
        #expect(before.allSatisfy { $0.copy == nil })
        #expect(before.map(\.value).prefix(2) == ["Not chosen yet", "Not chosen yet"])
        #expect(!model.canEditPorts && !model.canCopyEnvironment && !model.canSendTestEmail && !model.canOpenInbox)
        #expect(model.testEmailUnavailableReason == "Install Mailpit, then start mail to send a test email.")
        #expect(model.status == DisplayStatus("Not installed", tone: .idle))
        #expect(model.summary.status.label == "Not installed")
        model.requestRuntimeInstall()
        await model.confirmRuntimeInstall()?.value
        let after = MailConnectionSection.values(model)
        #expect(after.first?.label == "Host" && after.allSatisfy { $0.label != "SMTP server" })
        #expect(after.contains { $0.label == "SMTP port" && $0.copy != nil })
        #expect(model.canEditPorts && model.canCopyEnvironment && model.status.label == "Stopped")
        #expect(model.testEmailUnavailableReason == "Start mail to send a test email.")
    }

    @Test("Install asks first, then installs and registers Mailpit without a start")
    func installAfterConfirmation() async {
        let (fixture, mail) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        model.requestRuntimeInstall()
        #expect(
            model.pendingRuntimeInstall == ServiceRuntimeRequest(offer: SampleServices.mailOffer, startsService: false))
        #expect(await mail.calls == ["load"])
        await model.confirmRuntimeInstall()?.value
        #expect(await mail.calls == ["load", "install mailpit"])
        #expect(model.hasRuntime && model.runtimeInstallation == nil && model.runtimeNotice == nil)
        #expect(!model.state.isRunning)
        // An installed Mailpit is not offered again.
        model.requestRuntimeInstall()
        #expect(model.pendingRuntimeInstall == nil)
    }

    @Test("Start without Mailpit installs it first, then starts mail, in one flow")
    func startInstallsFirst() async {
        let (fixture, mail) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(model.start() == nil)
        #expect(model.pendingRuntimeInstall?.startsService == true)
        #expect(await mail.calls == ["load"])
        await model.confirmRuntimeInstall()?.value
        await waitUntil { model.state.isRunning }
        #expect(await mail.calls == ["load", "install mailpit", "start"])
        #expect(model.canSendTestEmail && model.canOpenInbox && model.inboxUnavailableReason == nil)
    }

    @Test("The card and the menu bar ask on the Mail page in the front window")
    func cardRequestShowsTheMailPage() async throws {
        let (fixture, _) = await launched()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.navigation.show(.dashboard(.overview))
        let before = fixture.shell.windowRequests
        try #require(state.mail.summary.actions.first).perform()
        #expect(state.navigation.section == .mail)
        #expect(fixture.shell.windowRequests == before + 1)
        #expect(state.mail.pendingRuntimeInstall?.startsService == true)
    }

    @Test("Progress shows in bytes; Cancel installs nothing and says so")
    func cancelInstallsNothing() async {
        let (fixture, mail) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        model.requestRuntimeInstall(startsService: true)
        let task = model.confirmRuntimeInstall()
        await waitUntil { model.runtimeInstallation?.progress != nil }
        #expect(model.runtimeInstallation?.message == "Downloading Mailpit 1.31.3… 3.9\u{00A0}MB of 9.8\u{00A0}MB")
        #expect(model.status.label == "Installing…")
        #expect(model.summary.summary == model.runtimeInstallation?.message)
        #expect(!model.canStart && !model.canInstallRuntime && model.isBusy)
        model.cancelRuntimeInstall()
        await task?.value
        #expect(
            model.runtimeNotice == ServiceRuntimeNotice(message: ServiceRuntimeCopy.mail.cancelled, isFailure: false))
        #expect(!model.hasRuntime && model.runtimeInstallation == nil)
        #expect(await mail.calls == ["load", "install mailpit"])
    }

    @Test("A failed install shows the reason once, starts nothing, and can be dismissed")
    func failureShowsTheReason() async {
        let offline = "Jerd cannot reach the download server. Check the network connection, then try again."
        let (fixture, mail) = await launched(behavior: .fail(offline))
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        model.requestRuntimeInstall(startsService: true)
        await model.confirmRuntimeInstall()?.value
        #expect(model.runtimeNotice == ServiceRuntimeNotice(message: offline, isFailure: true))
        #expect(model.operation == .idle)
        #expect(await mail.calls == ["load", "install mailpit"])
        model.dismissRuntimeNotice()
        #expect(model.runtimeNotice == nil && model.canInstallRuntime)
    }

    @Test("Quit cancels a running install before its final rename and clears a waiting request")
    func quitCancelsTheInstall() async {
        let (fixture, _) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        model.requestRuntimeInstall()
        _ = model.confirmRuntimeInstall()
        await waitUntil { model.runtimeInstallation?.progress != nil }
        #expect(await model.shutdown())
        #expect(!model.hasRuntime && model.runtimeInstallation == nil)
        model.resumeAfterCancelledQuit()
        model.requestRuntimeInstall()
        #expect(model.pendingRuntimeInstall != nil)
        _ = await model.shutdown()
        #expect(model.pendingRuntimeInstall == nil)
    }

    @Test("An app without a pinned Mailpit leads to Runtimes, as before")
    func noPinLeadsToRuntimes() async {
        let (fixture, _) = await launched(offer: nil)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        #expect(!model.canStart && !model.canInstallRuntime)
        #expect(model.summary.summary == "Mailpit is not installed. Install it in Runtimes.")
    }

    @Test("Mail, Storage, and Runtimes wait for each other's install")
    func pagesWaitForEachOther() async throws {
        let storage = InMemoryStorage()
        await storage.configure {
            $0.offer = SampleServices.storageOffer
            $0.installBehavior = .suspend(RuntimeInstallProgress("Downloading RustFS 1.0.0…", 0.2))
        }
        let (fixture, _) = await launched(
            behavior: Self.waiting, storage: storage,
            runtimes: InMemoryRuntimeInventory(inventory: SampleData.onDemandInventory))
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.mail.requestRuntimeInstall()
        let mailTask = state.mail.confirmRuntimeInstall()
        await waitUntil { state.mail.runtimeInstallation?.progress != nil }
        let reason = "The Mail page is installing Mailpit 1.31.3. Installs wait until it finishes."
        #expect(state.storage.runtimeInstallElsewhere?() == reason)
        #expect(state.databases.runtimeInstallElsewhere?() == reason)
        #expect(state.runtimes.runtimeInstallElsewhere?() == reason)
        #expect(!state.storage.canInstallRuntime && !state.runtimes.canInstallRuntimes)
        state.mail.cancelRuntimeInstall()
        await mailTask?.value

        state.storage.requestRuntimeInstall()
        let storageTask = state.storage.confirmRuntimeInstall()
        await waitUntil { state.storage.runtimeInstallation?.progress != nil }
        #expect(!state.mail.canInstallRuntime && !state.mail.canStart)
        #expect(state.mail.startUnavailableReason?.hasPrefix("The Storage page is installing RustFS") == true)
        state.storage.cancelRuntimeInstall()
        await storageTask?.value
        #expect(state.mail.canInstallRuntime)
    }

    @Test("The words: the size, the source, the space, the reuse, and the start")
    func installCopy() {
        let copy = ServiceRuntimeCopy.mail
        let offer = SampleServices.mailOffer
        let install = ServiceRuntimeRequest(offer: offer, startsService: false)
        let start = ServiceRuntimeRequest(offer: offer, startsService: true)
        #expect(copy.installTitle == "Install Mailpit…")
        #expect(copy.confirmationTitle(install) == "Install Mailpit 1.31.3?")
        #expect(copy.confirmTitle(install) == "Download and Install")
        #expect(copy.confirmTitle(start) == "Download and Start")
        let message = copy.confirmationMessage(install)
        #expect(message.contains("9.8\u{00A0}MB from github.com") && message.contains("reviewed checksum"))
        #expect(message.contains("36.2\u{00A0}MB of free disk space") && !message.contains("signature"))
        #expect(copy.confirmationMessage(start).hasSuffix("Then Jerd starts mail."))
        #expect(copy.notInstalledDetail(offer) == "Not installed. 1.31.3, 9.8\u{00A0}MB download.")
        #expect(copy.portsNotChosen == "Jerd chooses two free ports on this Mac when it installs Mailpit.")
        #expect(copy.failedTitle == "Mailpit was not installed")

        let reuse = ServiceRuntimeRequest(offer: offer.reusing(), startsService: false)
        #expect(copy.confirmTitle(reuse) == "Install")
        #expect(
            copy.confirmTitle(ServiceRuntimeRequest(offer: offer.reusing(), startsService: true)) == "Install and Start"
        )
        #expect(copy.confirmationMessage(reuse).contains("Nothing is downloaded"))
        #expect(copy.cardNotice(offer.reusing()) == "Mailpit is not in use yet. Start uses the copy on this Mac.")
        #expect(
            copy.footer(reuses: true)
                == "Mail needs Mailpit. Jerd uses the copy that is already on this Mac. Nothing is downloaded.")
        #expect(
            copy.footer(reuses: false)
                == "Mail needs Mailpit. Jerd downloads it only when you install it or start mail.")
        #expect(ServiceRuntimeCopy.storage.footer(reuses: false).hasPrefix("Storage needs RustFS."))
        #expect(offer.reusing().requiredSpace == 0 && offer.requiredSpace == 36_176_318)
    }

    @Test("Runtimes offers Mailpit with the same words while it is not installed")
    func runtimesOffersMailpit() throws {
        #expect(RuntimeCopy.footer(.mailpit, checkedAt: nil, isInstalled: false)?.contains("start mail") == true)
        #expect(RuntimeCopy.footer(.mailpit, checkedAt: nil)?.contains("An update restarts") == true)
        #expect(
            RuntimeCopy.installedMessage(.mailpit, version: "1.31.3", useAsDefault: true)
                == "Mailpit 1.31.3 is in use. Captured messages stay in the inbox.")
        let release = try #require(SampleData.onDemandReleases.first { $0.kind == .mailpit })
        #expect(SampleData.onDemandInventory.installableRelease(.mailpit) == release)
        let request = ServiceRuntimeRequest(offer: SampleServices.mailOffer, startsService: false)
        #expect(
            RuntimeInstallCopy.confirmationMessage(release, reuses: false)
                == ServiceRuntimeCopy.mail.confirmationMessage(request))
    }
}
