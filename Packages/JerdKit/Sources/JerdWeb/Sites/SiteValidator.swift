import Foundation
import JerdFoundation

/// Normalizes and validates one site against the other registered sites.
///
/// The checks run in a fixed order, so the first broken rule decides the message:
/// name, hostname, paths, containment, document root confirmation, duplicates, hosts conflict.
public struct SiteValidator: Sendable {
    private let files: any ProjectFileInspecting

    public init(files: any ProjectFileInspecting = PathCanonicalizer()) {
        self.files = files
    }

    /// Returns the normalized site: a trimmed name, a lowercase hostname, and canonical paths.
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
        guard !HostsConflictCheck.hasConflict(hostname: site.hostname, hostsText: hostsText) else {
            throw JerdError.invalid("This hostname has a conflicting /etc/hosts entry. Choose another hostname.")
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

    /// Nested projects are allowed; an equal project path or hostname is not.
    private func requireUnique(_ site: Site, among existing: [Site]) throws {
        for other in existing where other.id != site.id {
            guard other.hostname.lowercased() != site.hostname else {
                throw JerdError.invalid("This hostname is already registered.")
            }
            guard other.projectPath != site.projectPath else {
                throw JerdError.invalid("This project directory is already registered.")
            }
        }
    }
}
