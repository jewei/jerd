import AppKit
import CryptoKit
import Sparkle

// This executable belongs only to the isolated updater integration test.
@MainActor
final class TestDriver: NSObject, SPUUserDriver {
    var retryTermination: (() -> Void)?
    var updater: SPUUpdater?
    private var finished = false

    func record(_ event: String) {
        let path = Bundle.main.object(forInfoDictionaryKey: "TestResultPath") as! String
        let file = URL(fileURLWithPath: path)
        let data = Data((event + "\n").utf8)
        if !FileManager.default.fileExists(atPath: path) { try! data.write(to: file) }
        else {
            let handle = try! FileHandle(forWritingTo: file)
            try! handle.seekToEnd()
            try! handle.write(contentsOf: data)
            try! handle.close()
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

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("found:" + appcastItem.versionString)
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("no-update")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
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
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                             retryTerminatingApplication: @escaping () -> Void) {
        retryTermination = retryTerminatingApplication
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func dismissUpdateInstallation() {}
}

@MainActor
final class TestDelegate: NSObject, NSApplicationDelegate {
    let driver = TestDriver()
    var terminationRequests = 0
    var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        driver.record("pid:" + String(ProcessInfo.processInfo.processIdentifier))
        driver.record("launched:" + version)
        if version == "2" { driver.finish("updated"); return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        driver.updater = updater
        do {
            try updater.start()
            updater.checkForUpdates()
        } catch { driver.finish("startup-error:" + error.localizedDescription) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        terminationRequests += 1
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        let refuse = Bundle.main.object(forInfoDictionaryKey: "TestRefuseFirstQuit") as? Bool ?? false
        if refuse && version == "1" && terminationRequests == 1 {
            quitting = true
            driver.record("quit-deferred-refusal")
            let timer = Timer(timeInterval: 1, repeats: false) { [self] _ in
                MainActor.assumeIsolated {
                    driver.record("quit-refused")
                    quitting = false
                    sender.reply(toApplicationShouldTerminate: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                        let info = NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"))
                        driver.record("version-after-refusal:" + (info?["CFBundleVersion"] as? String ?? "missing"))
                        driver.retryTermination?()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return .terminateLater
        }
        quitting = true
        driver.record("quit-deferred:" + version)
        let timer = Timer(timeInterval: 1, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                driver.record("quit-approved:" + version)
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return .terminateLater
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "generate-test-key" {
    let key = Curve25519.Signing.PrivateKey()
    let file = URL(fileURLWithPath: CommandLine.arguments[2])
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else {
    let application = NSApplication.shared
    let delegate = TestDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
