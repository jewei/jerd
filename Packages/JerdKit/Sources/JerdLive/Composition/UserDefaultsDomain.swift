import Foundation

/// The persistent domain of the app, for example `dev.jerd.app`, through `UserDefaults.standard`,
/// which reads and writes that domain.
@MainActor
struct UserDefaultsDomain: PreferenceDomain {
    let name: String

    func read() -> [String: Any] {
        UserDefaults.standard.persistentDomain(forName: name) ?? [:]
    }

    func write(_ value: Any, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
