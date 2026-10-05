import Darwin

/// Readable text for a POSIX error number, for messages that must keep the system cause.
public enum SystemError {
    /// Returns the `strerror` text for `code`, for example "No such file or directory".
    public static func describe(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}
