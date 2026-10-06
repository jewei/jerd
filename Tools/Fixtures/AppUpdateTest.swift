// The test app of `./dev check updates`. The tool compiles this file with `swiftc` against the
// resolved Sparkle framework; it is never part of the Tools package. The app runs Sparkle with a
// user driver that answers every question, writes each event as one line to `TestResultPath`, and
// never loads Jerd settings or services.
import AppKit
import CryptoKit
import Sparkle

/// Answers Sparkle without a window and records what happens.
@MainActor
final class TestDriver: NSObject, SPUUserDriver {
    var retryTermination: (() -> Void)?
    var updater: SPUUpdater?
    private var finished = false

    func record(_ event: String) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "TestResultPath") as? String else { return }
        let data = Data((event + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    func finish(_ event: String) {
        guard !finished else { return }
        finished = true
        record(event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.terminate(nil)
        }
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(
        with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        record("found:" + appcastItem.versionString)
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("no-update")
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        var current: NSError? = error as NSError
        while let failure = current {
            record("error:" + failure.domain + ":" + String(failure.code) + ":" + failure.localizedDescription)
            current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        acknowledgement()
        finish("failed")
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() { record("extracting") }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("ready")
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void
    ) {
        retryTermination = retryTerminatingApplication
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {}
}

/// Starts Sparkle in version 1, and defers every quit by one second, as Jerd does while it stops services.
/// With `TestRefuseFirstQuit`, version 1 refuses the first quit and then lets Sparkle retry.
@MainActor
final class TestDelegate: NSObject, NSApplicationDelegate {
    let driver = TestDriver()
    var terminationRequests = 0
    var quitting = false

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "missing" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        driver.record("pid:" + String(ProcessInfo.processInfo.processIdentifier))
        driver.record("launched:" + version)
        if version == "2" {
            driver.finish("updated")
            return
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        driver.updater = updater
        do {
            try updater.start()
            updater.checkForUpdates()
        } catch {
            driver.finish("startup-error:" + error.localizedDescription)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        terminationRequests += 1
        quitting = true
        let refuses = Bundle.main.object(forInfoDictionaryKey: "TestRefuseFirstQuit") as? Bool ?? false
        if refuses && version == "1" && terminationRequests == 1 {
            driver.record("quit-deferred-refusal")
            after(seconds: 1) { [self] in refuseQuit(sender) }
        } else {
            driver.record("quit-deferred:" + version)
            after(seconds: 1) { [self] in
                driver.record("quit-approved:" + version)
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    private func refuseQuit(_ sender: NSApplication) {
        driver.record("quit-refused")
        quitting = false
        sender.reply(toApplicationShouldTerminate: false)
        after(seconds: 1) { [self] in
            let info = NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"))
            driver.record("version-after-refusal:" + (info?["CFBundleVersion"] as? String ?? "missing"))
            driver.retryTermination?()
        }
    }

    /// Runs `body` on the main run loop in every mode, so it also runs during a modal termination wait.
    private func after(seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "generate-test-key" {
    let key = Curve25519.Signing.PrivateKey()
    let file = URL(fileURLWithPath: CommandLine.arguments[2])
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = TestDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
