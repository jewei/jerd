import Foundation
import JerdFoundation
import JerdSystem
import Testing

@testable import JerdHelperCore

@Suite struct HelperServiceTests {
    private let owner = ServiceHarness.owner

    @Test func listenersNeedAReadySetup() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        await #expect(throws: JerdError.unavailable("Approved host and certificate setup is required.")) {
            try await harness.service.acquire(owner: owner, connection: UUID(), lifetime: SessionLifetime())
        }
        try await harness.service.configure(harness.request(), owner: owner, consent: harness.consent)
        let pair = try await harness.service.acquire(owner: owner, connection: UUID(), lifetime: SessionLifetime())
        #expect(try pair.ports().http > 1_023)
    }

    /// Fixed problem 11: a legacy hostname policy gets no listeners.
    @Test func theLegacyHostnamePolicyGetsNoListeners() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        try await harness.service.configure(harness.request(policy: .hostnames), owner: owner, consent: harness.consent)
        await #expect(throws: JerdError.unavailable("Approve HTTPS setup again so that browsers trust the Jerd CA.")) {
            try await harness.service.acquire(owner: owner, connection: UUID(), lifetime: SessionLifetime())
        }
    }

    @Test func theLeaseIsPerConnectionAndBlocksChanges() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        try await harness.service.configure(harness.request(), owner: owner, consent: harness.consent)
        let (first, second) = (UUID(), UUID())
        let pair = try await harness.service.acquire(owner: owner, connection: first, lifetime: SessionLifetime())
        let again = try await harness.service.acquire(owner: owner, connection: first, lifetime: SessionLifetime())
        #expect(again.http === pair.http)
        await #expect(throws: JerdError.unavailable("Another Jerd connection owns the standard ports.")) {
            try await harness.service.acquire(owner: owner, connection: second, lifetime: SessionLifetime())
        }
        await #expect(throws: JerdError.invalid("Stop Jerd's environment before removing system setup.")) {
            try await harness.service.remove(owner: owner, consent: harness.consent)
        }
        await harness.service.release(connection: second)
        await #expect(throws: JerdError.self) {
            try await harness.service.configure(harness.request(), owner: owner, consent: harness.consent)
        }
        await harness.service.release(connection: first)
        #expect(throws: JerdError.invalid("The loopback listeners are closed.")) { try pair.ports() }
        try await harness.service.remove(owner: owner, consent: harness.consent)
    }

    @Test func aClosedConnectionGetsNoListeners() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        try await harness.service.configure(harness.request(), owner: owner, consent: harness.consent)
        let lifetime = SessionLifetime()
        lifetime.invalidate()
        await #expect(throws: JerdError.unavailable("The helper connection was closed.")) {
            try await harness.service.acquire(owner: owner, connection: UUID(), lifetime: lifetime)
        }
        _ = try await harness.service.acquire(owner: owner, connection: UUID(), lifetime: SessionLifetime())
    }

    /// Fixed problem 22: a payload that is too large has its own message.
    @Test func oversizedPayloadsHaveTheirOwnMessage() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let message = JerdError.invalid("The request to the Jerd helper is too large. No change was made.")
        await #expect(throws: message) {
            try await harness.service.configure(Data(count: 131_072), owner: owner, consent: harness.consent)
        }
        await #expect(throws: message) {
            try await harness.service.recover(Data(count: 4_096), owner: owner, consent: harness.consent)
        }
    }

    @Test func aChangeReservesThePortsBeforeItStarts() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let blocked = HelperService(
            store: SetupStore(
                directory: RootRecordDirectory(url: harness.folder.appendingPathComponent("helper"), owner: getuid()),
                hosts: GuardedFileSwap(url: harness.folder.appendingPathComponent("hosts"), expectedOwner: getuid()),
                trust: FakeInspector(consent: harness.consent)),
            binder: FailingBinder(), keychain: harness.keychain, inspector: FakeInspector(consent: harness.consent))
        await #expect(throws: JerdError.unavailable("Port 80 is busy.")) {
            try await blocked.configure(harness.request(), owner: owner, consent: harness.consent)
        }
        #expect(harness.consent.requests.withLock { $0 }.isEmpty)
        try await blocked.remove(owner: owner, consent: harness.consent)
    }

    @Test func statusIsEncodedForTheWire() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let data = try await harness.service.status(owner: owner)
        #expect(try JSONDecoder().decode(SystemSetupStatus.self, from: data) == .empty)
    }
}

private struct FailingBinder: ListenerBinding {
    func bindStandardPorts() throws -> LoopbackListenerPair { throw JerdError.unavailable("Port 80 is busy.") }
}
