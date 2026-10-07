import Foundation
import Testing

@testable import JerdDevKit

@Suite("Update case cleanup")
struct UpdateCaseCleanupTests {
    static let home = URL(filePath: "/Users/me")
    static let identifier = "dev.jerd.updater-test.0123456789abcdef0123456789abcdef"

    @Test("The plan names the plist, the URL storage, the cookies, the caches, and the saved state")
    func planNamesEveryPath() {
        let paths = UpdateCaseCleanup(home: Self.home, bundleIdentifier: Self.identifier).paths.map(\.path)
        #expect(
            paths == [
                "/Users/me/Library/Preferences/\(Self.identifier).plist",
                "/Users/me/Library/HTTPStorages/\(Self.identifier)",
                "/Users/me/Library/HTTPStorages/\(Self.identifier).binarycookies",
                "/Users/me/Library/Caches/\(Self.identifier)",
                "/Users/me/Library/Saved Application State/\(Self.identifier).savedState",
            ])
    }

    @Test("Only a test identifier is removed: never the app, a path, or an empty suffix")
    func onlyTestIdentifiers() {
        for identifier in [
            "dev.jerd.app", "dev.jerd.updater-test.", "dev.jerd.updater-test.../x", "dev.jerd.updater-test.A1",
            "dev.jerd.updater-test.a/b", "com.example.dev.jerd.updater-test.a",
        ] {
            #expect(UpdateCaseCleanup(home: Self.home, bundleIdentifier: identifier).paths.isEmpty, "\(identifier)")
        }
        #expect(UpdateCaseCleanup.isTestIdentifier(Self.identifier))
    }

    @Test("Removes what exists, keeps other domains, and accepts paths that are absent")
    func removesExistingFiles() throws {
        let home = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try TestFixtures.write("<plist/>", to: "Library/Preferences/\(Self.identifier).plist", in: home)
        try TestFixtures.write("x", to: "Library/HTTPStorages/\(Self.identifier)/httpstorages.sqlite", in: home)
        try TestFixtures.write("<plist/>", to: "Library/Preferences/dev.jerd.app.plist", in: home)
        try UpdateCaseCleanup(home: home, bundleIdentifier: Self.identifier).removeFiles()
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "Library/Preferences").path)
                == ["dev.jerd.app.plist"])
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "Library/HTTPStorages").path)
                .isEmpty)
    }
}
