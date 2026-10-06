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

    @Test func changesRunInOrderAndErrorsCarryTheirCode() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let session = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        let payload = try harness.request()
        let (replies, reply) = AsyncStream<String>.makeStream()
        session.configureSite(payload) { reply.yield("configure \($0 ?? "ok")") }
        session.removeSetup { reply.yield("remove \($0 ?? "ok")") }
        var received: [String] = []
        for await text in replies.prefix(2) { received.append(text) }
        #expect(received == ["configure ok", "remove ok"])
        #expect(try await harness.service.setupStatus(owner: ServiceHarness.owner) == .empty)
        #expect(await change { session.configureSite(payload, reply: $0) } == nil)
        #expect(await acquire(session) == nil)
        let other = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: harness.consent)
        #expect(await acquire(other) == "Another Jerd connection owns the standard ports. (JERD-UNAVAILABLE)")
        await withCheckedContinuation { continuation in session.releaseListeners { continuation.resume() } }
        #expect(await acquire(other) == nil)
    }

    /// Fixed review M1: listener calls never wait behind a change that waits for macOS approval.
    /// The old helper refused them at once; a queued call timed out in the app and dropped the link.
    @Test func listenerCallsDuringAnOpenApprovalReplyAtOnce() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let held = HeldConsent(harness.consent)
        let session = HelperSession(owner: ServiceHarness.owner, service: harness.service, consent: held)
        let payload = try harness.request()
        async let configured = change { session.configureSite(payload, reply: $0) }
        await held.waitUntilAsked()
        let acquired: String?? = await FirstReply.within(.seconds(2)) { reply in
            session.acquireListeners { _, _, error in reply(error) }
        }
        let released: Bool? = await FirstReply.within(.seconds(2)) { reply in
            session.releaseListeners { reply(true) }
        }
        held.release()
        #expect(acquired == .some("System setup is in progress. Retry shortly. (JERD-UNAVAILABLE)"))
        #expect(released == true)
        #expect(await configured == nil)
        #expect(await acquire(session) == nil)
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
