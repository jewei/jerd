import Foundation
import JerdWeb

/// One entry of the PHP selection picker: follow the default, a registered runtime, or a pin
/// to a runtime that is no longer registered.
public struct PHPChoice: Hashable, Sendable {
    public let selection: PHPSelection
    public let title: String

    /// The entries for a site: Follow Default, each runtime, and the missing pin when there is one.
    public static func choices(
        runtimes: [DevelopmentRuntime], defaultRuntimeID: UUID?, current: PHPSelection
    ) -> [PHPChoice] {
        let defaultVersion = runtimes.first { $0.id == defaultRuntimeID }.map { " (PHP \($0.version))" } ?? ""
        var choices = [PHPChoice(selection: .followDefault, title: "Follow Default\(defaultVersion)")]
        choices += runtimes.map { runtime in
            PHPChoice(
                selection: .pinned(runtime.id),
                title: "PHP \(runtime.version) — \(runtime.id.uuidString.prefix(6))")
        }
        if case .pinned(let id) = current, !runtimes.contains(where: { $0.id == id }) {
            choices.append(PHPChoice(selection: current, title: "Pinned runtime unavailable"))
        }
        return choices
    }

    /// The PHP row of the site page, for example "Follow default: PHP 8.4.12".
    public static func summary(for site: Site, in configuration: AppConfiguration) -> String {
        let prefix = site.phpSelection == .followDefault ? "Follow default" : "Pinned"
        guard let runtime = try? configuration.runtime(for: site) else {
            return "\(prefix): runtime unavailable"
        }
        return "\(prefix): PHP \(runtime.version)"
    }
}
