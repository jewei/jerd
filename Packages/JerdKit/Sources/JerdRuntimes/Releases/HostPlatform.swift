import Foundation
import JerdManifest

/// The Mac that a release must run on: its architecture and macOS major version.
public struct HostPlatform: Hashable, Sendable {
    public let architecture: CPUArchitecture
    public let osMajor: Int

    public init(architecture: CPUArchitecture, osMajor: Int) {
        self.architecture = architecture
        self.osMajor = osMajor
    }

    /// The running Mac.
    public static var current: HostPlatform {
        HostPlatform(
            architecture: .current, osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}
