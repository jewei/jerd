import Foundation
import JerdFoundation
import JerdManifest

/// Installs the bundled payloads on first launch and returns typed records for registration.
///
/// Each group installs into its own Application Support folder. Installed folders are verified,
/// never replaced, and kept when a newer app installs another payload beside them.
public actor BundledRuntimeBootstrap {
    private let source: BundledPayloadSource
    private let layout: DataLayout
    private let companions: CLICompanionStore

    /// - Parameter resources: `Jerd.app/Contents/Resources/RuntimePayloads`.
    public init(resources: URL, layout: DataLayout, architecture: CPUArchitecture = .current) {
        source = BundledPayloadSource(root: resources, architecture: architecture)
        self.layout = layout
        companions = CLICompanionStore(layout: layout)
    }

    /// Rule B1: the development group is needed when PHP or Caddy is not configured or when the
    /// CLI tool record is missing or has no versions. A corrupt record throws and is preserved.
    public func needsDevelopmentRuntimes(hasPHP: Bool, hasCaddy: Bool) throws -> Bool {
        guard let record = try companions.load() else { return true }
        return !hasPHP || !hasCaddy || !record.hasVersions
    }

    /// Installs PHP, Caddy, Composer, and the Laravel installer, then records the CLI tools (B7).
    public func installDevelopment() async throws -> BundledDevelopmentRuntimes {
        let installed = try await install(.development, into: layout.runtimes.developmentRuntimesDirectory)
        func payload(_ kind: RuntimeKind) throws -> InstalledPayload {
            guard let payload = installed.first(where: { $0.kind == kind }) else {
                throw JerdError.invalid("The runtime payload is incomplete.")
            }
            return payload
        }
        let composer = try payload(.composer)
        let laravel = try payload(.laravel)
        let record = try companions.recordBundled(
            CLICompanions(
                composerPath: composer.executable.path, laravelPath: laravel.executable.path,
                composerVersion: composer.version, laravelVersion: laravel.version))
        return BundledDevelopmentRuntimes(
            php: try payload(.php), caddy: try payload(.caddy), composer: composer, laravel: laravel,
            companions: record)
    }

    /// Installs MySQL, PostgreSQL, and Redis, except the kinds in `excluding`.
    public func installDatabases(excluding: Set<RuntimeKind> = []) async throws -> [InstalledPayload] {
        try await install(.database, into: layout.runtimes.databaseRuntimesDirectory, excluding: excluding)
    }

    /// Installs Mailpit.
    public func installMail() async throws -> InstalledPayload {
        try await single(.mail, into: layout.runtimes.mailRuntimesDirectory)
    }

    /// Installs RustFS (with its XZ library in release builds).
    public func installStorage() async throws -> InstalledPayload {
        try await single(.storage, into: layout.runtimes.storageRuntimesDirectory)
    }

    /// Removes the staging folders that a crash or a kill left in the four group folders (P-I6, RT-7).
    ///
    /// A staging folder whose installation still runs, in this or another process, holds its lock
    /// and is kept. Call it at launch. Installed payload folders are never touched.
    /// - Returns: `<group folder>/<name>` of each removed folder.
    @discardableResult
    public func removeAbandonedStaging() -> [String] {
        PayloadGroup.allCases.map { layout.runtimes.payloadDirectory(for: $0) }.flatMap { directory in
            StagingFolder.removeAbandoned(in: directory).map { "\(directory.lastPathComponent)/\($0)" }
        }
    }

    /// The reviewed XZ library of the bundled RustFS payload, for managed RustFS updates (P-I1).
    /// Nil when the bundled payload has none (development builds).
    public func bundledLZMA() throws -> SupportLibrary? {
        guard let payload = try source.payloads(in: .storage).first else { return nil }
        let files = payload.receipt.fileRecords.keys.map(\.string)
        guard files.contains(LZMALinker.libraryName), files.contains(LZMALinker.licenseName) else { return nil }
        try VerifiedPayloadInstaller.verify(payload.origin, receipt: payload.receipt)
        return SupportLibrary(
            library: payload.origin.appendingPathComponent(LZMALinker.libraryName),
            license: payload.origin.appendingPathComponent(LZMALinker.licenseName))
    }

    private func install(
        _ group: PayloadGroup, into directory: URL, excluding: Set<RuntimeKind> = []
    ) async throws -> [InstalledPayload] {
        let installer = VerifiedPayloadInstaller(directory: directory)
        var installed: [InstalledPayload] = []
        for payload in try source.payloads(in: group) where !excluding.contains(payload.pin.kind) {
            installed.append(try await installer.install(payload))
        }
        return installed
    }

    private func single(_ group: PayloadGroup, into directory: URL) async throws -> InstalledPayload {
        guard let payload = try await install(group, into: directory).first else {
            throw JerdError.unavailable("The app has no bundled \(group.rawValue) runtimes.")
        }
        return payload
    }
}
