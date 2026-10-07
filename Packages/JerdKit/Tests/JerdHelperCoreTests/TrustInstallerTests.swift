import Foundation
import JerdFoundation
import JerdSystem
import Security
import Testing

@testable import JerdHelperCore

@Suite struct TrustInstallerTests {
    private func installer(_ keychain: FakeKeychain, _ consent: FakeConsent?) -> TrustInstaller {
        TrustInstaller(
            keychain: keychain, inspector: FakeInspector(consent: consent ?? FakeConsent()), consent: consent)
    }

    @Test func installAddsTheCAAndAsksTheApp() async throws {
        let (keychain, consent) = (FakeKeychain(), FakeConsent())
        let trust = try HelperFixture.trust()
        try await installer(keychain, consent).install(trust, replacingOwned: false)
        #expect(keychain.items.withLock { $0 } == [try HelperFixture.der()])
        #expect(consent.requests.withLock { $0 } == [trust.consentRequest])
    }

    @Test func withoutConsentNothingChanges() async throws {
        let keychain = FakeKeychain()
        await #expect(throws: JerdError.unavailable("The app must approve certificate changes.")) {
            try await installer(keychain, nil).install(try HelperFixture.trust(), replacingOwned: false)
        }
        await #expect(throws: JerdError.self) {
            try await installer(keychain, nil).remove(try HelperFixture.trust().certificate)
        }
        #expect(keychain.items.withLock { $0 }.isEmpty)
    }

    @Test func anUntrackedExistingCAIsRefusedAndKept() async throws {
        let (keychain, consent) = (FakeKeychain(), FakeConsent())
        _ = try keychain.add(try HelperFixture.der())
        await #expect(
            throws: JerdError.invalid("This CA already exists outside Jerd's tracked setup. It was not changed.")
        ) {
            try await installer(keychain, consent).install(try HelperFixture.trust(), replacingOwned: false)
        }
        #expect(keychain.items.withLock { $0 }.count == 1)
        #expect(consent.requests.withLock { $0 }.isEmpty)
    }

    @Test func anOwnedCAWithMatchingTrustNeedsNoNewApproval() async throws {
        let (keychain, consent) = (FakeKeychain(), FakeConsent())
        let trust = try HelperFixture.trust()
        try await installer(keychain, consent).install(trust, replacingOwned: false)
        try await installer(keychain, consent).install(trust, replacingOwned: true)
        #expect(consent.requests.withLock { $0 }.count == 1)
    }

    /// Regression test: an item that this call added is deleted on any failure, also an interruption.
    @Test(arguments: [FakeConsent.Answer.interrupted, .status(errSecAuthFailed)])
    func aFailedApprovalDeletesTheItemThisCallAdded(answer: FakeConsent.Answer) async throws {
        let keychain = FakeKeychain()
        await #expect(throws: JerdError.self) {
            try await installer(keychain, FakeConsent(answer)).install(try HelperFixture.trust(), replacingOwned: false)
        }
        #expect(keychain.items.withLock { $0 }.isEmpty)
    }

    @Test func aFailedApprovalKeepsAnItemThatExistedBefore() async throws {
        let keychain = FakeKeychain()
        _ = try keychain.add(try HelperFixture.der())
        await #expect(throws: JerdError.self) {
            try await installer(keychain, FakeConsent(.status(errSecAuthFailed))).install(
                try HelperFixture.trust(), replacingOwned: true)
        }
        #expect(keychain.items.withLock { $0 }.count == 1)
    }

    @Test func aFailedCleanupIsAPartialChange() async throws {
        let keychain = FakeKeychain()
        keychain.failDelete.withLock { $0 = true }
        do {
            try await installer(keychain, FakeConsent(.interrupted)).install(
                try HelperFixture.trust(), replacingOwned: false)
            Issue.record("Expected a failure")
        } catch let error as JerdError {
            #expect(error.kind == .partialChange)
            #expect(error.message.hasPrefix("Certificate trust approval failed, and the Jerd certificate may remain"))
        }
    }

    @Test func removeAsksTheAppThenDeletesTheItem() async throws {
        let (keychain, consent) = (FakeKeychain(), FakeConsent())
        let trust = try HelperFixture.trust()
        try await installer(keychain, consent).install(trust, replacingOwned: false)
        try await installer(keychain, consent).remove(trust.certificate)
        #expect(keychain.items.withLock { $0 }.isEmpty)
        #expect(consent.requests.withLock { $0 }.last == .removal(of: try HelperFixture.der()))
    }

    @Test func aRefusedRemovalKeepsTheItem() async throws {
        let keychain = FakeKeychain()
        _ = try keychain.add(try HelperFixture.der())
        await #expect(throws: JerdError.self) {
            try await installer(keychain, FakeConsent(.status(errSecAuthFailed))).remove(
                try HelperFixture.trust().certificate)
        }
        #expect(keychain.items.withLock { $0 }.count == 1)
        try await installer(keychain, FakeConsent(.status(errSecItemNotFound))).remove(
            try HelperFixture.trust().certificate)
        #expect(keychain.items.withLock { $0 }.isEmpty)
    }
}
