import Darwin
import Foundation
import JerdFoundation

/// The one reader and writer of `environment/installation-id`: an uppercase UUID without a newline.
///
/// The ID names the installation CA, so it never changes once written. A file that is not a
/// UUID is corrupt and preserved. Creation is exclusive, so two app instances that start at the
/// same moment still agree on one ID.
public struct InstallationIdentity: Sendable {
    /// The read limit of the file.
    public static let sizeLimit = 128

    public let file: URL

    public init(environment: EnvironmentLayout) {
        file = environment.installationIDFile
    }

    /// The saved ID, or nil when the file is absent.
    /// - Throws: `.corrupt` for a file that is not a UUID or not a private regular file.
    public func read() throws -> UUID? {
        guard FileProbe.presence(at: file).mayExist else { return nil }
        let data = try AtomicFile.read(file, limit: Self.sizeLimit)
        guard let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else {
            throw JerdError.corrupt("The installation identity is invalid. It was preserved.")
        }
        return id
    }

    /// The saved ID, or a new one that is saved first.
    public func readOrCreate() throws -> UUID {
        if let id = try read() { return id }
        try OwnedDirectory.create(file.deletingLastPathComponent())
        let staged = file.deletingLastPathComponent().appendingPathComponent(".installation-id-\(UUID().uuidString)")
        try AtomicFile.write(Data(UUID().uuidString.utf8), to: staged)
        // An exclusive rename never replaces an existing file and never shows a second link:
        // the first writer wins and the others read its ID.
        let renamed = renamex_np(staged.path, file.path, UInt32(RENAME_EXCL)) == 0
        let failure = errno
        if !renamed { unlink(staged.path) }
        guard renamed || failure == EEXIST else {
            throw JerdError.unavailable("Cannot save the installation identity (\(SystemError.describe(failure))).")
        }
        guard let id = try read() else {
            throw JerdError.unavailable("Cannot save the installation identity.")
        }
        return id
    }
}
