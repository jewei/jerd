/// A Mac processor architecture. The raw values are saved in pins and folder names.
public enum CPUArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64
    /// Intel Macs. The raw value is the Mach-O architecture name.
    case intel = "x86_64"

    /// The architecture of the running process.
    public static var current: CPUArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .intel
        #endif
    }

    /// The Go-style name that some publishers use in file names (`arm64` or `amd64`).
    public var goName: String { self == .arm64 ? "arm64" : "amd64" }

    /// The Rust-style name that some publishers use in file names (`aarch64` or `x86_64`).
    public var rustName: String { self == .arm64 ? "aarch64" : "x86_64" }
}
