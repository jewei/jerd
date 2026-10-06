import AppKit
import Foundation
import JerdFoundation
import JerdUI
import Testing

@testable import JerdLive

@Suite("App shell mappings")
struct AppShellMappingTests {
    @Test func everyTerminationAnswerHasItsApplicationReply() {
        #expect(TerminationReply.now.applicationReply == .terminateNow)
        #expect(TerminationReply.later.applicationReply == .terminateLater)
        #expect(TerminationReply.cancel.applicationReply == .terminateCancel)
    }

    @Test func theDockSwitchSelectsTheActivationPolicy() {
        #expect(AppPresence.activationPolicy(showInDock: true) == .regular)
        #expect(AppPresence.activationPolicy(showInDock: false) == .accessory)
    }

    @Test(arguments: [("main", true), ("main-AppWindow-1", true), ("mainly", false), (nil, false), ("about", false)])
    func theMainWindowIsFoundByItsSceneID(identifier: String?, isMain: Bool) {
        #expect(MainWindowPresenter.isMainWindow(identifier: identifier) == isMain)
    }

    @Test func updateCycleErrorsMapToTheAboutPageResults() {
        let domain = UpdateCycleMapping.sparkleErrorDomain
        #expect(UpdateCycleMapping.result(for: nil) == .completed)
        #expect(UpdateCycleMapping.result(for: NSError(domain: domain, code: 1001)) == .noUpdate)
        #expect(UpdateCycleMapping.result(for: NSError(domain: domain, code: 4007)) == .cancelled)
        #expect(
            UpdateCycleMapping.result(for: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                == .cancelled)
        let failure = NSError(domain: domain, code: 3002, userInfo: [NSLocalizedDescriptionKey: "Bad signature."])
        #expect(UpdateCycleMapping.result(for: failure) == .failed("Bad signature."))
    }

    @MainActor
    @Test func aCheckDuringQuitIsRefusedAsAUserCancellation() {
        let error = UpdateCycleMapping.stoppingError()

        #expect(error.domain == NSCocoaErrorDomain)
        #expect(error.code == NSUserCancelledError)
        #expect(error.localizedDescription == AppUpdatesModel.stoppingMessage)
        #expect(UpdateCycleMapping.result(for: error) == .cancelled)
    }

    @Test func theFeedMustBeTheOfficialSignedFeed() throws {
        let bundle = try Self.bundle(info: [
            "SUFeedURL": "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml",
            "SUPublicEDKey": "FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA=",
        ])
        #expect(
            try UpdateCycleMapping.feedURL(in: bundle)
                == "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml")

        let unexpanded = try Self.bundle(info: [
            "SUFeedURL": "$(JERD_UPDATE_FEED_URL)", "SUPublicEDKey": "$(JERD_UPDATE_PUBLIC_KEY)",
        ])
        #expect(throws: JerdError.self) { try UpdateCycleMapping.feedURL(in: unexpanded) }

        let other = try Self.bundle(info: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA=",
        ])
        #expect(throws: JerdError.self) { try UpdateCycleMapping.feedURL(in: other) }
    }

    @MainActor
    @Test func iconImagesComeFromTheAppIconsFolderAndAreCached() throws {
        let bundle = try Self.bundle(info: [:])
        let folder = bundle.bundleURL.appendingPathComponent("Contents/Resources/AppIcons", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.png().write(to: folder.appendingPathComponent("Icon-dots.png"))
        let images = AppIconImages(bundle: bundle)

        let image = try #require(images.image(for: .dots))
        let small = try #require(images.menuBarImage(for: .dots))

        #expect(images.image(for: .dots) === image)
        #expect(small.size == AppIconImages.menuBarSize)
        #expect(!small.isTemplate)
        #expect(images.image(for: .monogram) == nil)
    }

    @MainActor
    @Test func openPanelsSelectOneItemOfTheRequestedKind() {
        let executable = SheetFilePanels.panel(for: .executable("Select a trusted Caddy 2 executable."))
        #expect(executable.canChooseFiles && !executable.canChooseDirectories)
        #expect(!executable.allowsMultipleSelection)
        #expect(executable.prompt == "Select Executable")

        let folder = SheetFilePanels.panel(for: FilePanelRequest(kind: .folder, message: "Project", prompt: "Choose"))
        #expect(folder.canChooseDirectories && !folder.canChooseFiles)
    }

    /// A minimal app bundle in a temporary folder with the given Info.plist keys.
    static func bundle(info: [String: String]) throws -> Bundle {
        let root = try Fixture.temporaryFolder().appendingPathComponent("Test.app", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        var plist = info
        plist["CFBundleIdentifier"] = "dev.jerd.tests.\(UUID().uuidString)"
        plist["CFBundlePackageType"] = "APPL"
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
    }

    /// A 2 × 2 PNG.
    static func png() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.systemPink.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
