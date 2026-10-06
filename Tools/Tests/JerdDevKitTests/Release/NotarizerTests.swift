import Foundation
import Testing

@testable import JerdDevKit

@Suite("Notarization")
struct NotarizerTests {
    static let id = "2F1D4D8E-1C55-4C55-9C55-1C551C551C55"

    static func notarizer(_ workspace: ReleaseWorkspace) throws -> (Notarizer, CandidateLayout) {
        let layout = CandidateLayout(root: workspace.path("candidate"))
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        let credentials = try NotaryCredentials(profile: "notary", keychain: nil)
        return (Notarizer(shell: try workspace.shell(), credentials: credentials, layout: layout), layout)
    }

    @Test("An accepted submission returns its ID, keeps the result, and staples the ticket")
    func accepted() async throws {
        let workspace = try ReleaseWorkspace()
        workspace.runner.on(
            "xcrun", ["notarytool", "submit"], output: #"{"id":"\#(Self.id)","status":"Accepted"}"#,
            error: "Conducting pre-submission checks…\nprogress: 50%")
        let (notarizer, layout) = try Self.notarizer(workspace)
        let id = try await notarizer.notarize(
            URL(filePath: "/c/app.zip"), name: "app", staple: URL(filePath: "/c/Jerd.app"))
        #expect(id == Self.id)
        #expect(FileManager.default.fileExists(atPath: layout.file("app-notary.json").path))
        #expect(FileManager.default.fileExists(atPath: layout.log("app-notary").path))
        let submit = try #require(workspace.runner.calls("xcrun", ["notarytool", "submit"]).first)
        #expect(
            submit == [
                "notarytool", "submit", "/c/app.zip", "--keychain-profile", "notary", "--wait", "--timeout", "45m",
                "--output-format", "json",
            ])
        #expect(workspace.runner.calls("xcrun", ["stapler"]) == [["stapler", "staple", "/c/Jerd.app"]])
    }

    @Test("An invalid result with a failing exit status still fetches the issues log and stops")
    func invalidFetchesTheLog() async throws {
        let workspace = try ReleaseWorkspace()
        workspace.runner.on(
            "xcrun", ["notarytool", "submit"], status: 69, output: #"{"id":"\#(Self.id)","status":"Invalid"}"#)
        let (notarizer, layout) = try Self.notarizer(workspace)
        await #expect(throws: DevFailure.self) {
            try await notarizer.notarize(URL(filePath: "/c/x.dmg"), name: "dmg", staple: URL(filePath: "/c/x.dmg"))
        }
        let log = try #require(workspace.runner.calls("xcrun", ["notarytool", "log"]).first)
        #expect(
            log == [
                "notarytool", "log", Self.id, "--keychain-profile", "notary",
                layout.file("dmg-notary-issues.json").path,
            ])
        #expect(workspace.runner.calls("xcrun", ["stapler"]).isEmpty)
    }

    @Test("A run without a JSON result stops and staples nothing")
    func noResult() async throws {
        let workspace = try ReleaseWorkspace()
        workspace.runner.on(
            "xcrun", ["notarytool", "submit"], status: 1, error: "Error: No Keychain password item found")
        let (notarizer, _) = try Self.notarizer(workspace)
        await #expect(throws: DevFailure.self) {
            try await notarizer.notarize(URL(filePath: "/c/x.zip"), name: "app", staple: URL(filePath: "/c/Jerd.app"))
        }
        #expect(workspace.runner.calls("xcrun", ["notarytool", "log"]).isEmpty)
        #expect(workspace.runner.calls("xcrun", ["stapler"]).isEmpty)
    }
}
