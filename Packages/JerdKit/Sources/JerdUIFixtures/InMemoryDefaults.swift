import Foundation
import os

/// A defaults object that keeps its values in memory only. A suite domain leaves a file in
/// `~/Library/Preferences` even after `removePersistentDomain`, so tests and snapshots use this
/// instead. It answers the reads and writes that the UI uses; it never reads the real domains.
///
/// `UserDefaults` is `Sendable`, so this subclass must be too: every value sits behind one
/// unfair lock, which makes each access atomic.
public final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private let values = OSAllocatedUnfairLock<[String: Any]>(uncheckedState: [:])

    /// - Parameter name: A label for messages only; nothing is stored under it.
    public override init?(suiteName name: String?) {
        super.init(suiteName: nil)
    }

    public override func object(forKey defaultName: String) -> Any? {
        values.withLockUnchecked { $0[defaultName] }
    }

    public override func set(_ value: Any?, forKey defaultName: String) {
        values.withLockUnchecked { $0[defaultName] = value }
    }

    public override func set(_ value: Bool, forKey defaultName: String) {
        set(value as Any?, forKey: defaultName)
    }

    public override func removeObject(forKey defaultName: String) {
        values.withLockUnchecked { $0[defaultName] = nil }
    }

    public override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    public override func bool(forKey defaultName: String) -> Bool {
        object(forKey: defaultName) as? Bool ?? false
    }

    public override func dictionaryRepresentation() -> [String: Any] {
        values.withLockUnchecked { $0 }
    }

    /// Removes every value.
    public func removeAll() {
        values.withLockUnchecked { $0.removeAll() }
    }
}
