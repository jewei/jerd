import Foundation

/// One edit of the site configuration. Every change, also runtime records, goes through
/// `SiteChangeTransaction`, so a running site always follows the saved records.
public enum SiteChange: Equatable, Sendable {
    /// Add or replace a site (matched by ID). `confirmed` is the document root confirmation.
    case save(Site, confirmed: Bool)
    /// Change "Include when starting all sites".
    case enabled(UUID, Bool)
    /// Remove a site. A missing ID changes nothing.
    case remove(UUID)
    /// Select the default PHP runtime.
    case defaultRuntime(UUID)
    /// Select the Caddy executable.
    case caddy(CaddyRuntime)
    /// Add an inspected runtime, or replace the record with the same CLI and FPM paths (its ID stays).
    case upsertRuntime(DevelopmentRuntime)
    /// Remove a runtime that is neither the default nor pinned by a site.
    case removeRuntime(UUID)
}
