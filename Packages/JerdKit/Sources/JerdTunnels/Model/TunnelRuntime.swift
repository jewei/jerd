import Foundation
import JerdFoundation

/// A cloudflared executable that Jerd checked, saved as `runtime` in `tunnels/settings.json`.
public struct TunnelRuntime: Codable, Equatable, Hashable, Sendable {
    /// `cloudflared-<version>` for every runtime that this build saves.
    public let id: String
    public let version: String
    /// The absolute folder that contains the `cloudflared` executable.
    public let path: String

    package init(id: String, version: String, path: String) {
        self.id = id
        self.version = version
        self.path = path
    }

    /// A checked runtime. The installer and the file picker both use this initializer, so one
    /// runtime always gets one ID (earlier builds used three ID forms).
    public init(version: String, directory: URL) {
        self.init(id: "cloudflared-\(version)", version: version, path: directory.standardizedFileURL.path)
    }

    /// The `cloudflared` executable in `path`.
    public var executable: URL {
        URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("cloudflared", isDirectory: false)
    }

    /// Requires a safe ID and version and an absolute path without control characters.
    public func validate() throws {
        guard Self.isSafeIdentifier(id), Self.isSafeIdentifier(version), path.hasPrefix("/"),
            !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw JerdError.invalid(TunnelMessage.invalidRuntime) }
    }

    /// 1 to 100 characters of `A-Z a-z 0-9 - .`, and not `.` or `..`.
    static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value != "." && value != ".."
            && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
                    || byte == 46
            }
    }
}
