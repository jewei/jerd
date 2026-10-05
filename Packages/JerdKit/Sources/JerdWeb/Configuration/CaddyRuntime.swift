/// An inspected Caddy 2 executable. The property names are the saved JSON keys.
public struct CaddyRuntime: Codable, Equatable, Hashable, Sendable {
    public let path: String
    /// The trimmed output of `caddy version`, for example `v2.11.4 h1:…`.
    public let version: String
    public let architectures: [CPUArchitecture]

    public init(path: String, version: String, architectures: [CPUArchitecture]) {
        self.path = path
        self.version = version
        self.architectures = architectures
    }
}
