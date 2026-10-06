import Foundation
import JerdFoundation
import Testing

@testable import JerdLive

@Suite("Launch preparation")
struct LaunchPreparationTests {
    actor RecordingCleaner: StagingCleaning {
        private(set) var count = 0
        func removeAbandonedStaging() -> [String] {
            count += 1
            return ["runtimes/.staging-1"]
        }
    }

    actor RecordingLauncher: LauncherRefreshing {
        private(set) var count = 0
        private(set) var ranOnMainThread = false
        let failure: JerdError?

        init(failure: JerdError? = nil) { self.failure = failure }

        func refreshLauncherIfInstalled() throws -> Bool {
            count += 1
            ranOnMainThread = Thread.isMainThread
            if let failure { throw failure }
            return true
        }
    }

    @Test func everyStagingFolderIsCleanedAndTheLauncherRefreshedOnceOffTheMainThread() async {
        let first = RecordingCleaner()
        let second = RecordingCleaner()
        let launcher = RecordingLauncher()

        await LaunchPreparation(staging: [first, second], launcher: launcher).run()

        #expect(await first.count == 1)
        #expect(await second.count == 1)
        #expect(await launcher.count == 1)
        #expect(await !launcher.ranOnMainThread)
    }

    @Test func aFailedLauncherRefreshDoesNotStopTheLaunch() async {
        let launcher = RecordingLauncher(failure: .invalid("The launcher signature does not match."))

        await LaunchPreparation(staging: [], launcher: launcher).run()

        #expect(await launcher.count == 1)
    }

    @Test func aSeparateDataRootLeavesTheUsersLauncherAlone() async throws {
        let configuration = LiveConfiguration(
            layout: try Fixture.layout(), appBundle: URL(fileURLWithPath: "/Applications/Jerd.app"),
            resources: URL(fileURLWithPath: "/Applications/Jerd.app/Contents/Resources"), appVersion: "1.0")

        #expect(!configuration.usesCurrentUserData)
        #expect(LiveConfiguration(bundle: .main).usesCurrentUserData)
    }
}
