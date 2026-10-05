import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteChangeReducerTests {
    let reducer = SiteChangeReducer(hosts: FakeHostsFile())

    @Test func saveAppendsANewSiteAndReplacesAnExistingOne() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let draft = Samples.site(folder.url)
        let added = try reducer.reduce(Samples.configuration([]), .save(draft, confirmed: true))
        #expect(added.sites.map(\.id) == [draft.id])
        var renamed = draft
        renamed.displayName = "Renamed"
        let replaced = try reducer.reduce(added, .save(renamed, confirmed: true))
        #expect(replaced.sites.map(\.displayName) == ["Renamed"])
    }

    @Test func saveChecksTheHostsFileAndOtherChangesDoNotReadIt() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let draft = Samples.site(folder.url)
        let conflicting = SiteChangeReducer(hosts: FakeHostsFile(text: "10.0.0.1 demo.test"))
        #expect(throws: JerdError.self) {
            try conflicting.reduce(Samples.configuration([]), .save(draft, confirmed: true))
        }
        let unreadable = SiteChangeReducer(hosts: FakeHostsFile(error: .unavailable("Cannot read /etc/hosts.")))
        let configuration = Samples.configuration([draft])
        #expect(throws: JerdError.unavailable("Cannot read /etc/hosts.")) {
            try unreadable.reduce(configuration, .save(draft, confirmed: true))
        }
        #expect(try !unreadable.reduce(configuration, .enabled(draft.id, false)).sites[0].isEnabled)
    }

    @Test func missingRecordsAreRefusedAndAMissingRemovalIsANoOp() throws {
        let configuration = Samples.configuration([Samples.site(URL(fileURLWithPath: "/p/a"))])
        #expect(throws: JerdError.invalid("The site record is missing.")) {
            try reducer.reduce(configuration, .enabled(UUID(), true))
        }
        #expect(throws: JerdError.invalid("The runtime record is missing.")) {
            try reducer.reduce(configuration, .defaultRuntime(UUID()))
        }
        #expect(try reducer.reduce(configuration, .remove(UUID())) == configuration)
        #expect(try reducer.reduce(configuration, .remove(configuration.sites[0].id)).sites.isEmpty)
    }

    @Test func defaultRuntimeAndCaddyAreSet() throws {
        let second = Samples.runtime()
        var configuration = Samples.configuration([])
        configuration.runtimes.append(second)
        #expect(try reducer.reduce(configuration, .defaultRuntime(second.id)).defaultRuntimeID == second.id)
        #expect(try reducer.reduce(configuration, .caddy(Samples.caddy(path: "/c"))).caddy?.path == "/c")
    }

    @Test func upsertKeepsTheIDOfTheSamePathsAndSetsAMissingDefault() throws {
        let original = Samples.runtime(version: "8.4.0")
        var configuration = AppConfiguration()
        configuration = try reducer.reduce(configuration, .upsertRuntime(original))
        #expect(configuration.defaultRuntimeID == original.id)
        let updated = Samples.runtime(id: UUID(), version: "8.4.1")
        configuration = try reducer.reduce(configuration, .upsertRuntime(updated))
        #expect(configuration.runtimes.count == 1)
        #expect(configuration.runtimes[0].id == original.id && configuration.runtimes[0].version == "8.4.1")
        let other = Samples.runtime(cli: "/other/php", fpm: "/other/php-fpm")
        configuration = try reducer.reduce(configuration, .upsertRuntime(other))
        #expect(configuration.runtimes.map(\.id) == [original.id, other.id])
        #expect(configuration.defaultRuntimeID == original.id)
    }

    @Test func aDefaultOrPinnedRuntimeCannotBeRemoved() throws {
        let pinned = Samples.runtime()
        let spare = Samples.runtime()
        var configuration = Samples.configuration([
            Samples.site(URL(fileURLWithPath: "/p/a"), selection: .pinned(pinned.id))
        ])
        configuration.runtimes += [pinned, spare]
        let message = JerdError.invalid("Reassign the default and all pinned sites before removing this runtime.")
        #expect(throws: message) { try reducer.reduce(configuration, .removeRuntime(Samples.runtimeID)) }
        #expect(throws: message) { try reducer.reduce(configuration, .removeRuntime(pinned.id)) }
        #expect(
            try reducer.reduce(configuration, .removeRuntime(spare.id)).runtimes.map(\.id) == [
                Samples.runtimeID, pinned.id,
            ])
    }

    @Test func runtimeResolutionUsesThePinOrTheDefaultWithoutFallback() throws {
        let pinned = Samples.runtime()
        var configuration = Samples.configuration([])
        configuration.runtimes.append(pinned)
        var site = Samples.site(URL(fileURLWithPath: "/p/a"))
        #expect(try configuration.runtime(for: site).id == Samples.runtimeID)
        site.phpSelection = .pinned(pinned.id)
        #expect(try configuration.runtime(for: site).id == pinned.id)
        site.phpSelection = .pinned(UUID())
        let unavailable = JerdError.unavailable("The selected PHP runtime is unavailable. Select an installed runtime.")
        #expect(throws: unavailable) { try configuration.runtime(for: site) }
        configuration.defaultRuntimeID = nil
        site.phpSelection = .followDefault
        #expect(throws: unavailable) { try configuration.runtime(for: site) }
    }
}
