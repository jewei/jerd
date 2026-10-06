import Foundation
import JerdFoundation

/// Where the live app finds its bundle and its data, and the version it reports.
public struct LiveConfiguration: Sendable {
    /// The data root, normally `~/Library/Application Support/Jerd`.
    public let layout: DataLayout
    /// `Jerd.app`. The command-line tools copy their launcher from it.
    public let appBundle: URL
    /// `Jerd.app/Contents/Resources`.
    public let resources: URL
    /// `CFBundleShortVersionString`, for the user agent of runtime downloads.
    public let appVersion: String?

    public init(layout: DataLayout, appBundle: URL, resources: URL, appVersion: String?) {
        self.layout = layout
        self.appBundle = appBundle
        self.resources = resources
        self.appVersion = appVersion
    }

    /// The running app and the data root of the current user.
    public init(bundle: Bundle, layout: DataLayout = .currentUser()) {
        self.init(
            layout: layout, appBundle: bundle.bundleURL,
            resources: bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources"),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    /// `Contents/Resources/RuntimePayloads`: the bundled runtime payloads.
    public var payloads: URL { resources.appendingPathComponent("RuntimePayloads", isDirectory: true) }
}
