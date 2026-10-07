import Foundation
import Testing

@testable import JerdDevKit

@Suite("Disk image inspection")
struct DiskImageInspectionTests {
    static func setUp() throws -> (ReleaseWorkspace, URL) {
        let workspace = try ReleaseWorkspace()
        let app = workspace.path("export/Jerd.app")
        for path in ["Contents/Info.plist", "Contents/MacOS/Jerd", "Contents/_CodeSignature/CodeResources"] {
            try workspace.write(path, to: "export/Jerd.app/\(path)")
        }
        workspace.runner.on(
            "hdiutil", ["attach"],
            effect: { invocation in
                let mount = URL(filePath: invocation.arguments[4])
                try FileManager.default.copyItem(at: app, to: mount.appending(path: "Jerd.app"))
            })
        return (workspace, app)
    }

    @Test("Checks the image and the mounted app, then detaches")
    func inspects() async throws {
        let (workspace, app) = try Self.setUp()
        defer { workspace.remove() }
        try await DiskImageInspection(shell: workspace.shell(), team: ReleaseFixtures.team)
            .verify(URL(filePath: "/c/Jerd-0.2.0.dmg"), exportedApp: app)
        #expect(workspace.runner.calls("hdiutil").map(\.first!) == ["verify", "attach", "detach"])
        #expect(workspace.runner.calls("spctl").count == 2)
    }

    @Test("A failed detach is tried again with force")
    func forcesDetach() async throws {
        let (workspace, app) = try Self.setUp()
        defer { workspace.remove() }
        workspace.runner.on("hdiutil", ["detach"], status: 16, error: "resource busy")
        workspace.runner.on("hdiutil", ["detach", "-force"])
        try await DiskImageInspection(shell: workspace.shell(), team: ReleaseFixtures.team)
            .verify(URL(filePath: "/c/x.dmg"), exportedApp: app)
        #expect(workspace.runner.calls("hdiutil", ["detach"]).count == 2)
    }

    @Test("A different mounted app is reported, also when the detach fails")
    func keepsTheCheckError() async throws {
        let (workspace, app) = try Self.setUp()
        defer { workspace.remove() }
        workspace.runner.on(
            "hdiutil", ["attach"],
            effect: { invocation in
                let mount = URL(filePath: invocation.arguments[4])
                try FileManager.default.copyItem(at: app, to: mount.appending(path: "Jerd.app"))
                try Data("other".utf8).write(to: mount.appending(path: "Jerd.app/Contents/MacOS/Jerd"))
            })
        workspace.runner.on("hdiutil", ["detach"], status: 16)
        let inspection = DiskImageInspection(shell: try workspace.shell(), team: ReleaseFixtures.team)
        do {
            try await inspection.verify(URL(filePath: "/c/x.dmg"), exportedApp: app)
            Issue.record("The check passed.")
        } catch let failure as DevFailure {
            #expect(failure.message.contains("another app"))
        }
        #expect(workspace.output.all.contains("Could not detach"))
    }
}
