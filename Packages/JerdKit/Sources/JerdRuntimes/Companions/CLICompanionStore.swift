import Foundation
import JerdFoundation
import JerdManifest

/// The only reader and writer of `runtimes/cli-tools.json`.
///
/// A corrupt record is never reset: every operation throws and the bytes stay for inspection.
/// Call it from the one actor that owns runtime selection.
public struct CLICompanionStore: Sendable {
    /// The record is a few hundred bytes.
    public static let sizeLimit = 65_536

    private let store: JSONDocumentStore<CLICompanions>

    public init(file: URL) {
        store = JSONDocumentStore(
            file: file, sizeLimit: Self.sizeLimit, format: .compact, name: "the Composer and Laravel tool record",
            validate: Self.validate)
    }

    public init(layout: DataLayout) { self.init(file: layout.runtimes.cliToolsFile) }

    public var file: URL { store.file }

    /// The record, or nil when it does not exist.
    public func load() throws -> CLICompanions? { try store.load() }

    /// Rule B7: records the bundled tools after first-launch installation.
    ///
    /// Without a record, the bundled tools become the selection. With a record, its paths stay
    /// (a later managed selection survives); a missing version is filled only for a path that is the bundled one.
    @discardableResult
    public func recordBundled(_ bundled: CLICompanions) throws -> CLICompanions {
        guard let existing = try load() else {
            try store.save(bundled)
            return bundled
        }
        let merged = CLICompanions(
            composerPath: existing.composerPath, laravelPath: existing.laravelPath,
            composerVersion: existing.composerVersion
                ?? (existing.composerPath == bundled.composerPath ? bundled.composerVersion : nil),
            laravelVersion: existing.laravelVersion
                ?? (existing.laravelPath == bundled.laravelPath ? bundled.laravelVersion : nil))
        try store.save(merged)
        return merged
    }

    /// Rule I19: selects a managed Composer or Laravel installer build and keeps the other tool.
    /// - Throws: `.invalid` for another kind; `.unavailable` when no record exists yet.
    @discardableResult
    public func activate(_ runtime: ManagedRuntime) throws -> CLICompanions {
        guard runtime.kind == .composer || runtime.kind == .laravel else {
            throw JerdError.invalid("This runtime is not a CLI companion.")
        }
        guard let old = try load() else {
            throw JerdError.unavailable("Open Jerd to install its bundled Composer and Laravel installer first.")
        }
        let isComposer = runtime.kind == .composer
        let next = CLICompanions(
            composerPath: isComposer ? runtime.executable.path : old.composerPath,
            laravelPath: isComposer ? old.laravelPath : runtime.executable.path,
            composerVersion: isComposer ? runtime.version : old.composerVersion,
            laravelVersion: isComposer ? old.laravelVersion : runtime.version)
        try store.save(next)
        return next
    }

    private static func validate(_ companions: CLICompanions) throws {
        guard companions.composerPath.hasPrefix("/"), companions.laravelPath.hasPrefix("/") else {
            throw JerdError.invalid("The Composer and Laravel tool paths must be absolute.")
        }
    }
}
