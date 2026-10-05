import Foundation
import JerdFoundation
import JerdSystem
import Testing

@testable import JerdHelperCore

@Suite struct HelperSessionTests {
    private func change(_ body: (@escaping @Sendable (String?) -> Void) -> Void) async -> String? {
        await withCheckedContinuation { continuation in body { continuation.resume(returning: $0) } }
    }

    private func acquire(_ session: HelperSession) async -> String? {
        await withCheckedContinuation { continuation in
            session.acquireListeners { _, _, error in continuation.resume(returning: error) }
        }
    }

    @Test func requestsRunInOrderAndErrorsCarryTheirCode() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let session = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        let payload = try harness.request()
        async let configured = change { session.configureSite(payload, reply: $0) }
        async let acquired = acquire(session)
        #expect(await configured == nil)
        #expect(await acquired == nil)
        let other = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        #expect(await acquire(other) == "Another Jerd connection owns the standard ports. (JERD-UNAVAILABLE)")
        await withCheckedContinuation { continuation in session.releaseListeners { continuation.resume() } }
        #expect(await acquire(other) == nil)
    }

    @Test func aClosedSessionStartsNoQueuedChangeAndReleasesItsLease() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let session = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        let payload = try harness.request()
        #expect(await change { session.configureSite(payload, reply: $0) } == nil)
        #expect(await acquire(session) == nil)
        let closing = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        closing.invalidate()
        session.invalidate()
        let other = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        var error = await acquire(other)
        for _ in 0..<50 where error != nil {
            try await Task.sleep(for: .milliseconds(10))
            error = await acquire(other)
        }
        #expect(error == nil)
        let late = await change { closing.removeSetup(reply: $0) }
        #expect(late == "The helper connection was closed. (JERD-UNAVAILABLE)")
    }

    @Test func statusRepliesWithJSON() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let session = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        let data: Data? = await withCheckedContinuation { continuation in
            session.status { data, _ in continuation.resume(returning: data) }
        }
        #expect(try JSONDecoder().decode(SystemSetupStatus.self, from: #require(data)) == .empty)
    }
}
