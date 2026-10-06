/// One preferences domain with property list values. `UserDefaultsDomain` is the live type;
/// tests use a fake.
@MainActor
package protocol PreferenceDomain {
    func read() -> [String: Any]
    func write(_ value: Any, for key: String)
    func remove(_ key: String)
}
