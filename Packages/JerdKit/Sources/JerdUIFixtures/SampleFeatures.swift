import JerdUI

/// The states of the sample data. Every service feature is a real model on in-memory ports
/// (`InMemorySitesPort`, `InMemoryTunnelsPort`, `InMemoryServicePorts`), so no sample feature
/// is left; `all` stays for tests that inject an extra `InMemoryFeature`.
@MainActor
public enum SampleFeatures {
    /// Which state the sample data shows.
    public enum Variant: Sendable {
        case empty, populated, busy, long
    }

    /// No sample features: every section has its real feature.
    public static func all(_ variant: Variant) -> [InMemoryFeature] {
        []
    }
}
