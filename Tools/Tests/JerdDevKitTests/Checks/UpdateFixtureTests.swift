import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Update test apps, feed, and commands")
struct UpdateFixtureTests {
    /// Jerd's committed Info.plist.
    static let jerdInfoPlist = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: SparkleInfoPlistPolicy.file)

    static let bundle = UpdateTestBundle(
        bundleIdentifier: "dev.jerd.updater-test.abc", version: "1",
        feedURL: URL(string: "http://127.0.0.1:1234/appcast.xml")!, publicKey: "KEY",
        resultFile: URL(filePath: "/work/events.txt"), refusesFirstQuit: true)

    @Test("The test apps use every Sparkle key of Jerd's Info.plist, with only the feed and key replaced")
    func copiesJerdSparkleKeys() throws {
        let settings = try UpdateTestBundle.sparkleSettings(fromJerdInfoPlist: Data(contentsOf: Self.jerdInfoPlist))
        #expect(Set(settings.keys) == Set(SparkleInfoPlistPolicy.requiredValues.map(\.key)))
        let data = try Self.bundle.infoPlist(sparkleSettings: settings)
        let info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["SUFeedURL"] as? String == "http://127.0.0.1:1234/appcast.xml")
        #expect(info["SUPublicEDKey"] as? String == "KEY")
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["CFBundleVersion"] as? String == "1" && info["CFBundleShortVersionString"] as? String == "1.0")
        #expect(info["TestRefuseFirstQuit"] as? Bool == true && info["TestResultPath"] as? String == "/work/events.txt")
        #expect((info["NSAppTransportSecurity"] as? [String: Bool])?["NSAllowsLocalNetworking"] == true)
    }

    @Test("Refuses an Info.plist without the Sparkle feed and key")
    func refusesMissingKeys() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["SUEnableAutomaticChecks": false], format: .xml, options: 0)
        #expect(throws: DevFailure.self) { try UpdateTestBundle.sparkleSettings(fromJerdInfoPlist: data) }
        #expect(throws: DevFailure.self) { try UpdateTestBundle.sparkleSettings(fromJerdInfoPlist: Data("x".utf8)) }
    }

    @Test("The feed offers version 2 with the signed archive, or nothing")
    func feedText() throws {
        let archive = UpdateTestFeed.Archive(
            url: URL(string: "http://127.0.0.1:1234/update.zip")!, length: 4096, signature: "c2ln")
        let text = UpdateTestFeed.text(archive: archive)
        #expect(text.contains(#"<rss xmlns:sparkle="\#(Appcast.sparkleNamespace)" version="2.0">"#))
        #expect(text.contains("<sparkle:version>2</sparkle:version>"))
        #expect(
            text.contains(
                #"<enclosure url="http://127.0.0.1:1234/update.zip" length="4096" type="application/octet-stream" sparkle:edSignature="c2ln"/>"#
            ))
        #expect(try XMLDocument(data: Data(text.utf8)).rootElement()?.name == "rss")
        #expect(!UpdateTestFeed.text(archive: nil).contains("<item>"))
    }

    @Test("The altered feed changes the item title, and the altered archive differs in one bit")
    func alterations() throws {
        let feed = Data(
            UpdateTestFeed.text(archive: .init(url: URL(string: "http://h/a")!, length: 1, signature: "s")).utf8)
        #expect(String(decoding: try UpdateTestFeed.altered(feed), as: UTF8.self).contains("Updater Test 9.0"))
        #expect(throws: DevFailure.self) { try UpdateTestFeed.altered(Data(UpdateTestFeed.text(archive: nil).utf8)) }
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "update.zip")
        try Data(repeating: 0b1010, count: 200).write(to: file)
        try UpdateTestFeed.flipBit(in: file)
        let changed = try Data(contentsOf: file)
        #expect(changed[100] == 0b1011 && changed.count == 200 && changed.filter { $0 != 0b1010 }.count == 1)
    }

    @Test("Plans the exact compile, signing, and Sparkle commands")
    func plansCommands() {
        let plan = UpdateFixturePlan(repository: TestFixtures.repository, toolchain: TestFixtures.toolchain)
        let sparkle = "/work/jerd/.build/SourcePackages/artifacts/sparkle/Sparkle"
        let compile = plan.compile(to: URL(filePath: "/w/UpdaterTest"))
        #expect(compile.executable.path == "/usr/bin/xcrun")
        #expect(
            compile.arguments == [
                "swiftc", "-swift-version", "6", "-F", "\(sparkle)/Sparkle.xcframework/macos-arm64_x86_64",
                "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                "/work/jerd/Tools/Fixtures/AppUpdateTest.swift", "-o", "/w/UpdaterTest",
            ])
        let app = URL(filePath: "/w/new/Updater Test.app")
        #expect(
            plan.sign(app, identity: "ID").arguments == [
                "--force", "--deep", "--options", "runtime", "--sign", "ID", "/w/new/Updater Test.app",
            ])
        let key = URL(filePath: "/w/test-key")
        let archive = URL(filePath: "/w/update.zip")
        #expect(plan.signArchive(archive, key: key).executable.path == "\(sparkle)/bin/sign_update")
        #expect(
            plan.signArchive(archive, key: key).arguments == ["--ed-key-file", "/w/test-key", "-p", "/w/update.zip"])
        #expect(plan.zip(app, to: archive).arguments.prefix(4) == ["-c", "-k", "--sequesterRsrc", "--keepParent"])
        let generate = plan.generateKey(binary: URL(filePath: "/w/UpdaterTest"), key: key, inherited: ["A": "1"])
        #expect(generate.environment?["DYLD_FRAMEWORK_PATH"] == "\(sparkle)/Sparkle.xcframework/macos-arm64_x86_64")
        #expect(plan.launch(app).executable.path == "/w/new/Updater Test.app/Contents/MacOS/UpdaterTest")
        #expect(plan.deleteDefaults(bundleIdentifier: "b").arguments == ["delete", "b"])
    }
}
