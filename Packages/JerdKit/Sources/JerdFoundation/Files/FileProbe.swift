import Darwin
import Foundation

/// Answers "is something at this path?" with `lstat`, without following a final symbolic link.
public enum FileProbe {
    /// The three answers that `lstat` can prove. Only `absent` proves that nothing is there.
    public enum Presence: Equatable, Hashable, Sendable {
        /// `lstat` failed with `ENOENT`.
        case absent
        /// `lstat` succeeded. The item can be of any type, including a symbolic link.
        case present
        /// `lstat` failed with another error, for example `EACCES` or `ENOTDIR`.
        case unknown(errno: Int32)

        /// True unless absence is proven. Safety checks treat an unknown item as present.
        public var mayExist: Bool { self != .absent }
    }

    /// Returns what `lstat` proves about `url`.
    public static func presence(at url: URL) -> Presence {
        var info = stat()
        if lstat(url.path, &info) == 0 { return .present }
        let code = errno
        return code == ENOENT ? .absent : .unknown(errno: code)
    }
}
