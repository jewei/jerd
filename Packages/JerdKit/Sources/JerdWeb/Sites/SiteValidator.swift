import Foundation
import JerdFoundation

/// Normalizes and validates one site against the other registered sites.
///
/// The checks run in a fixed order, so the first broken rule decides the message:
/// name, hostname, aliases, paths, containment, document root confirmation, duplicates, the
/// total of names, hosts conflict.
public struct SiteValidator: Sendable {
    private let files: any ProjectFileInspecting

    public init(files: any ProjectFileInspecting = PathCanonicalizer()) {
        self.files = files
    }

    /// Returns the normalized site: a trimmed name, lowercase hostnames, sorted aliases, and
    /// canonical paths.
    /// `id`, `phpSelection`, and `isEnabled` do not change.
    ///
    /// - Parameters:
    ///   - existing: the registered sites. The site with the same ID is the old form of `draft`.
    ///   - hostsText: the text of `/etc/hosts`, or "" to skip the conflict check.
    ///   - documentRootConfirmed: the user confirmed the document root. A Laravel project with
    ///     its `public` folder as the root needs no confirmation.
    public func validate(
        _ draft: Site, existing: [Site], hostsText: String = "", documentRootConfirmed: Bool
    ) throws -> Site {
        var site = draft
        site.displayName = site.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.displayName.isEmpty else { throw JerdError.invalid("Enter a site name.") }
        site.hostname = try HostnamePolicy.validate(site.hostname).value
        site.aliases = try SiteAliases.validate(site.aliases, hostname: site.hostname)
        site.projectPath = try files.canonicalDirectory(site.projectPath)
        site.documentRoot = try files.canonicalDirectory(site.documentRoot)
        guard PathComponents.contains(site.documentRoot, in: site.projectPath) else {
            throw JerdError.invalid("The document root must be inside the project directory.")
        }
        let suggestion = try ProjectDetector(files: files).suggestDocumentRoot(projectPath: site.projectPath)
        guard documentRootConfirmed || (suggestion.isLaravel && suggestion.path == site.documentRoot) else {
            throw JerdError.invalid("Confirm the document root before saving this site.")
        }
        try requireUnique(site, among: existing)
        try requireNameCount(site, among: existing)
        guard !HostsConflictCheck.hasConflict(hostname: site.hostname, hostsText: hostsText) else {
            throw JerdError.invalid("This hostname has a conflicting /etc/hosts entry. Choose another hostname.")
        }
        for alias in site.aliases where HostsConflictCheck.hasConflict(hostname: alias, hostsText: hostsText) {
            throw JerdError.invalid("The alias \(alias) has a conflicting /etc/hosts entry. Choose another alias.")
        }
        return site
    }

    /// Validates every site of a serving plan again (paths can change after a save).
    public func revalidate(_ sites: [Site]) throws -> [Site] {
        var validated: [Site] = []
        for site in sites {
            validated.append(try validate(site, existing: validated, documentRootConfirmed: true))
        }
        return validated
    }

    /// One HTTPS setup holds at most 256 names, so a save must not pass that total; otherwise
    /// every later approval fails.
    private func requireNameCount(_ site: Site, among existing: [Site]) throws {
        let others = existing.filter { $0.id != site.id }.reduce(0) { $0 + $1.servedHostnames.count }
        guard others + site.servedHostnames.count <= HostnamePolicy.maximumSetCount else {
            throw JerdError.invalid(
                "Jerd serves at most \(HostnamePolicy.maximumSetCount) hostnames and aliases in all. Remove some aliases."
            )
        }
    }

    /// Nested projects are allowed; an equal project path, hostname, or alias is not.
    private func requireUnique(_ site: Site, among existing: [Site]) throws {
        for other in existing where other.id != site.id {
            let taken = Set(other.servedHostnames.map { $0.lowercased() })
            guard !taken.contains(site.hostname) else {
                throw JerdError.invalid("This hostname is already registered.")
            }
            if let alias = site.aliases.first(where: taken.contains) {
                throw JerdError.invalid("The alias \(alias) is already registered.")
            }
            guard other.projectPath != site.projectPath else {
                throw JerdError.invalid("This project directory is already registered.")
            }
        }
    }
}
