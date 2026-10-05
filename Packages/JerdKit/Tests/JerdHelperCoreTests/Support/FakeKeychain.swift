import Darwin
import Foundation
import JerdFoundation
import JerdSystem
import os

@testable import JerdHelperCore

/// An in-memory system keychain.
final class FakeKeychain: KeychainCertificateStoring, Sendable {
    let items = OSAllocatedUnfairLock(initialState: Set<Data>())
    let failDelete = OSAllocatedUnfairLock(initialState: false)

    func add(_ der: Data) throws -> KeychainAddOutcome {
        items.withLock { $0.insert(der).inserted } ? .added : .alreadyPresent
    }

    func deleteExact(_ der: Data) throws {
        if failDelete.withLock({ $0 }) { throw JerdError.unavailable("Cannot remove the Jerd root certificate: test") }
        _ = items.withLock { $0.remove(der) }
    }
}
