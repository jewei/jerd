import Foundation
import JerdFoundation
import JerdUI
import Testing

@testable import JerdLive

@Suite("Live app composition")
@MainActor
struct LiveAppTests {
    final class SilentUpdater: AppUpdating {
        func start(events: @escaping @MainActor (AppUpdateEvent) -> Void) throws -> AppUpdaterState {
            AppUpdaterState(canCheck: false, automaticallyChecks: false, lastCheck: nil)
        }
        func checkForUpdates() {}
        func setAutomaticChecks(_ isEnabled: Bool) -> Bool { false }
    }

    static func configuration() throws -> LiveConfiguration {
        let app = try Fixture.temporaryFolder().appendingPathComponent("Jerd.app", isDirectory: true)
        return LiveConfiguration(
            layout: try Fixture.layout(), appBundle: app, resources: app.appendingPathComponent("Contents/Resources"),
            appVersion: "0.1.0")
    }

    /// A defaults domain that the test only reads, so no preferences file is written.
    static func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "dev.jerd.live-tests.\(UUID().uuidString)"))
    }

    @Test func buildingTheAppWiresEveryFeatureAndChangesNothingOnDisk() throws {
        let configuration = try Self.configuration()

        let live = LiveApp(
            configuration: configuration, updater: SilentUpdater(), bundle: .main, defaults: try Self.defaults())

        #expect(live.state.features.map(\.section) == [.sites, .databases, .storage, .mail])
        #expect(!live.state.isLaunched)
        #expect(!FileManager.default.fileExists(atPath: configuration.layout.root.path))
    }

    @Test func aSeparateDataRootNeverRefreshesTheUsersLauncher() throws {
        let live = LiveApp(
            configuration: try Self.configuration(), updater: SilentUpdater(), bundle: .main,
            defaults: try Self.defaults())

        #expect(live.preparation.launcher == nil)
        #expect(live.preparation.staging.count == 2)
    }
}
