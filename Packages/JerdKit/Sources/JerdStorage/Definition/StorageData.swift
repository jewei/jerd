import Darwin
import Foundation
import JerdFoundation
import JerdServiceKit

/// The storage data: the RustFS volume `data/`, its runtime identity (`runtime.json`), the
/// credentials, the raw key files, and the marker of a successful start (`initialized.json`).
///
/// Rules:
/// - Data is never opened with another runtime, also not one in another folder.
/// - After a successful start, the volume format file and `credentials.json` must keep the hashes
///   in `initialized.json`. Any change refuses the start and keeps every file.
/// - Files in a data folder without an identity are never adopted, and credentials are created
///   only for an empty data folder.
/// - `credentials.json` is written once and never encoded again.
struct StorageData: Sendable {
    /// The largest file whose hash `initialized.json` records.
    static let hashedFileLimit = 65_535

    let layout: StorageLayout

    var identity: DataIdentityGuard<StorageRuntime> {
        DataIdentityGuard(
            file: layout.runtimeIdentityFile,
            messages: .init(mismatch: StorageMessages.identityMismatch, untracked: StorageMessages.untracked))
    }

    /// Prepares a start with `runtime` and returns the credentials. It creates the data folder,
    /// the identity, and the credentials only for new data. It writes the raw key files that
    /// RustFS reads on every start.
    func prepare(for runtime: StorageRuntime, generator: SecretGenerator = .system) throws -> StorageCredentials {
        try requireUnchangedIfInitialized(for: runtime)
        try OwnedDirectory.create(layout.dataDirectory, within: layout.root)
        try identity.admit(runtime, dataIsUntouched: try DataFolder.isAbsentOrEmpty(layout.dataDirectory))
        let stored: StoredCredentials
        if FileProbe.presence(at: layout.credentialsFile).mayExist {
            stored = try StoredCredentials.read(from: layout.credentialsFile)
            try Self.tightenMode(of: layout.credentialsFile)
        } else {
            guard try DataFolder.isAbsentOrEmpty(layout.dataDirectory) else { throw StorageMessages.credentialsMissing }
            stored = try StoredCredentials.create(at: layout.credentialsFile, using: generator)
        }
        try AtomicFile.write(Data(stored.credentials.accessKey.utf8), to: layout.accessKeyFile)
        try AtomicFile.write(Data(stored.credentials.secretKey.utf8), to: layout.secretKeyFile)
        return stored.credentials
    }

    /// Applies the rules of `prepare(for:)` without a write, for example before a runtime update.
    func validate(for runtime: StorageRuntime) throws {
        try requireUnchangedIfInitialized(for: runtime)
        let untouched = try DataFolder.isAbsentOrEmpty(layout.dataDirectory)
        if let saved = try identity.saved() {
            guard saved == runtime else { throw StorageMessages.identityMismatch }
        } else if !untouched {
            throw StorageMessages.untracked
        }
        if FileProbe.presence(at: layout.credentialsFile).mayExist {
            _ = try StoredCredentials.read(from: layout.credentialsFile)
        } else if !untouched {
            throw StorageMessages.credentialsMissing
        }
    }

    /// Moves the saved markers to `runtime` in a runtime update. The start marker gets fresh
    /// hashes of the unchanged files. Absent markers stay absent.
    func adopt(_ runtime: StorageRuntime) throws {
        if try identity.saved() != nil { try MarkerFile.write(runtime, to: layout.runtimeIdentityFile) }
        if FileProbe.presence(at: layout.initializedMarkerFile).mayExist { try markInitialized(runtime) }
    }

    /// Saves the marker of a successful start with the hashes of the format and credential files,
    /// unless the saved marker is equal.
    func markInitialized(_ runtime: StorageRuntime) throws {
        try MarkerFile.writeIfChanged(currentMarker(for: runtime), to: layout.initializedMarkerFile)
    }

    /// The saved credentials.
    func credentials() throws -> StorageCredentials {
        guard FileProbe.presence(at: layout.credentialsFile).mayExist else { throw StorageMessages.startOnce }
        return try StoredCredentials.read(from: layout.credentialsFile).credentials
    }

    /// A pure hash compare of the raw file bytes. The credentials are decoded only
    /// after it passes, so a changed credential file is reported as changed data.
    private func requireUnchangedIfInitialized(for runtime: StorageRuntime) throws {
        guard FileProbe.presence(at: layout.initializedMarkerFile).mayExist else { return }
        let saved = try MarkerFile.read(StorageInitializedMarker.self, from: layout.initializedMarkerFile)
        guard saved.runtime == runtime, try currentMarker(for: runtime) == saved else {
            throw StorageMessages.dataChanged
        }
    }

    /// The marker of the current files: the SHA-256 of the exact bytes of the format file and of
    /// `credentials.json`, which is never encoded again.
    private func currentMarker(for runtime: StorageRuntime) throws -> StorageInitializedMarker {
        StorageInitializedMarker(
            runtime: runtime, formatHash: try Self.hash(of: layout.formatFile),
            credentialsHash: try Self.hash(of: layout.credentialsFile))
    }

    /// The SHA-256 of a private regular file below 64 KiB.
    static func hash(of file: URL) throws -> String {
        do {
            return FileDigest.hexSHA256(of: try AtomicFile.read(file, limit: hashedFileLimit))
        } catch {
            throw StorageMessages.requiredFileInvalid
        }
    }

    /// Sets mode 0600 through one descriptor, never through a link.
    private static func tightenMode(of file: URL) throws {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw StorageMessages.requiredFileInvalid }
        defer { close(descriptor) }
        guard fchmod(descriptor, AtomicFile.fileMode) == 0 else {
            throw JerdError.unavailable("Cannot protect the storage credentials (\(SystemError.describe(errno))).")
        }
    }
}
