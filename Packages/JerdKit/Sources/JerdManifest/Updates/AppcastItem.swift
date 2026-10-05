import Foundation

/// One release in an appcast: the versions, the requirements, and the signed archive.
public struct AppcastItem: Equatable, Sendable {
    public let title: String?
    /// `sparkle:version`, the bundle version (`CFBundleVersion`).
    public let bundleVersion: String
    /// `sparkle:shortVersionString`, the marketing version.
    public let shortVersion: String?
    /// `sparkle:minimumSystemVersion`.
    public let minimumSystemVersion: String?
    /// `sparkle:hardwareRequirements`, for example `arm64`.
    public let hardwareRequirements: String?
    public let enclosure: AppcastEnclosure

    public init(
        title: String?, bundleVersion: String, shortVersion: String?, minimumSystemVersion: String?,
        hardwareRequirements: String?, enclosure: AppcastEnclosure
    ) {
        self.title = title
        self.bundleVersion = bundleVersion
        self.shortVersion = shortVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.hardwareRequirements = hardwareRequirements
        self.enclosure = enclosure
    }
}
