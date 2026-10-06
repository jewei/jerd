import JerdManifest
import JerdRuntimes

/// Chooses the release that the picker of a runtime selects after a check.
enum RuntimeSelectionPolicy {
    /// Keeps the user's selection while the check still offers it. Otherwise PHP prefers the
    /// newest release in the branch of the default PHP (for example 8.4.x for PHP 8.4.10);
    /// every other kind, and PHP without a match, selects the newest release.
    static func selection(
        after check: RuntimeUpdateCheck, current: String?, defaultPHPVersion: String?
    ) -> String? {
        if let current, check.releases.contains(where: { $0.id == current }) {
            return current
        }
        if check.kind == .php, let branch = defaultPHPVersion.flatMap(RuntimeVersion.init)?.prefix(2) {
            let preferred = check.releases.first { release in
                release.parsedVersion?.prefix(2) == branch
            }
            if let preferred { return preferred.id }
        }
        return check.releases.first?.id
    }
}
