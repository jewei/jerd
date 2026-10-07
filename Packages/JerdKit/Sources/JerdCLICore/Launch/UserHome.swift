import Darwin
import Foundation
import JerdFoundation

/// The home folder of the commands and of their shell setup, with the rule that zsh uses.
///
/// The PATH block says `$HOME/Library/Application Support/Jerd/bin`, so the launcher must read the
/// data root below the same `$HOME`. Foundation's `homeDirectoryForCurrentUser` ignores `HOME`.
/// Rule: an absolute, UTF-8 `HOME` wins; else (unset, empty, relative, or not UTF-8) the account home.
enum UserHome {
    /// The home folder for the `HOME` bytes `home` and the account home `account`. Pure.
    static func resolve(home: [UInt8]?, account: URL) -> URL {
        guard let home, home.first == UInt8(ascii: "/"), CStrings.isUTF8(home) else { return account }
        return URL(fileURLWithPath: String(decoding: home, as: UTF8.self), isDirectory: true).standardizedFileURL
    }

    /// The home folder of the current process.
    static func current() -> URL {
        resolve(
            home: getenv("HOME").map { CStrings.bytes($0) }, account: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Jerd's data root below `home`: `Library/Application Support/Jerd`, as in `DataLayout.currentUser()`.
    static func dataLayout(home: URL) -> DataLayout {
        DataLayout(
            root: home.appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Jerd", isDirectory: true))
    }
}
