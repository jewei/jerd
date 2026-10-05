/// A Mach-O architecture that Jerd can run. The raw value is the saved form and the `lipo` name.
public enum CPUArchitecture: String, Codable, Hashable, Sendable, CaseIterable {
    case arm64
    // The case name is the Mach-O and saved name, so it keeps its underscore.
    // swift-format-ignore: AlwaysUseLowerCamelCase
    case x86_64

    /// The architecture of the running process.
    public static var current: CPUArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }
}
