import Foundation

/// The version facts of the running app, for About.
public struct AppInfo: Equatable, Sendable {
    public let version: String
    public let build: String
    public let macOSVersion: String
    public let architecture: String
    public let copyright: String

    public init(version: String, build: String, macOSVersion: String, architecture: String, copyright: String) {
        self.version = version
        self.build = build
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.copyright = copyright
    }

    /// Reads the bundle and the process. Missing keys read as "Unknown".
    public init(bundle: Bundle, processInfo: ProcessInfo = .processInfo) {
        func value(_ key: String) -> String? { bundle.object(forInfoDictionaryKey: key) as? String }
        self.init(
            version: value("CFBundleShortVersionString") ?? "Unknown", build: value("CFBundleVersion") ?? "Unknown",
            macOSVersion: processInfo.operatingSystemVersionString, architecture: Self.currentArchitecture,
            copyright: value("NSHumanReadableCopyright") ?? "Copyright © 2026 Jerd contributors")
    }

    /// The architecture that this build runs as.
    public static var currentArchitecture: String {
        #if arch(arm64)
            "Apple Silicon (arm64)"
        #elseif arch(x86_64)
            "Intel (x86_64)"
        #else
            "Unknown"
        #endif
    }
}
