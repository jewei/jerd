import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteRegistryTests {
    @Test func everyCallBeforeALoadIsRefused() async {
        let registry = SiteRegistry(store: FakeConfigurationStore())
        await #expect(throws: JerdError.corrupt("Load valid site settings before making changes.")) {
            try await registry.snapshot()
        }
        await #expect(throws: JerdError.corrupt("Load a valid configuration before making changes.")) {
            try await registry.replace(AppConfiguration(), expecting: AppConfiguration())
        }
    }

    @Test func replaceSavesOnlyWhenTheSavedConfigurationIsUnchanged() async throws {
        let before = Samples.configuration([])
        let store = FakeConfigurationStore(before)
        let registry = SiteRegistry(store: store)
        #expect(try await registry.load() == before)
        var next = before
        next.caddy = Samples.caddy(path: "/new")
        await #expect(throws: JerdError.unavailable("The site settings changed. Review the edit again.")) {
            try await registry.replace(next, expecting: AppConfiguration())
        }
        #expect(await store.saves == 0)
        #expect(try await registry.replace(next, expecting: before) == next)
        #expect(await store.saved == next)
        #expect(try await registry.snapshot() == next)
    }

    @Test func aFailedSaveKeepsTheSnapshot() async throws {
        let before = Samples.configuration([])
        let store = FakeConfigurationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        await store.failNextSave()
        await #expect(throws: JerdError.self) { try await registry.replace(AppConfiguration(), expecting: before) }
        #expect(try await registry.snapshot() == before)
    }

    @Test func aSecondWriteOrLoadDuringASaveIsRefused() async throws {
        let before = Samples.configuration([])
        let store = FakeConfigurationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        await store.pauseNextSave()
        let first = Task { try await registry.replace(AppConfiguration(), expecting: before) }
        #expect(await waitUntil { await store.isPaused })
        await #expect(throws: JerdError.invalid("A configuration operation is in progress. Retry the change.")) {
            try await registry.replace(AppConfiguration(), expecting: before)
        }
        await #expect(throws: JerdError.invalid("A configuration operation is in progress.")) {
            try await registry.load()
        }
        await store.resume()
        #expect(try await first.value == AppConfiguration())
    }
}
