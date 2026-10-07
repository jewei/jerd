import Foundation

/// What one update case leaves in the user's Library for its random bundle identifier, and the
/// rule that only such paths are removed.
///
/// `defaults delete` empties the domain, but cfprefsd keeps the plist file, and URLSession of the
/// test app (Sparkle's feed and archive downloads) writes `HTTPStorages/<identifier>`. Each case
/// removes all of them at its end, also after a failure.
struct UpdateCaseCleanup: Equatable, Sendable {
    /// Every test bundle identifier starts with this prefix.
    static let identifierPrefix = "dev.jerd.updater-test."

    let home: URL
    let bundleIdentifier: String

    /// True for an identifier of a test app: the prefix and 1 to 64 lowercase letters or digits.
    static func isTestIdentifier(_ identifier: String) -> Bool {
        guard identifier.hasPrefix(identifierPrefix) else { return false }
        let suffix = identifier.dropFirst(identifierPrefix.count)
        return (1...64).contains(suffix.count)
            && suffix.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    /// The paths to remove, or none for an identifier that is not a test identifier.
    var paths: [URL] {
        guard Self.isTestIdentifier(bundleIdentifier) else { return [] }
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        return [
            library.appending(path: "Preferences/\(bundleIdentifier).plist"),
            library.appending(path: "HTTPStorages/\(bundleIdentifier)", directoryHint: .isDirectory),
            library.appending(path: "HTTPStorages/\(bundleIdentifier).binarycookies"),
            library.appending(path: "Caches/\(bundleIdentifier)", directoryHint: .isDirectory),
            library.appending(
                path: "Saved Application State/\(bundleIdentifier).savedState", directoryHint: .isDirectory),
        ]
    }

    /// Removes every path that exists. It tries each path, then reports the first failure.
    func removeFiles() throws {
        var failure: (any Error)?
        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            do {
                try FileManager.default.removeItem(at: path)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }
}
