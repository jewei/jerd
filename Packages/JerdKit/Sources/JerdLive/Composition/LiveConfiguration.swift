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
    /// True when the launch replaces an outdated command-line launcher in `bin/`. It starts true
    /// only for the current user's data root, because the launcher in `bin/` is the user's.
    public var refreshesCommandLineLauncher: Bool

    public init(layout: DataLayout, appBundle: URL, resources: URL, appVersion: String?) {
        self.layout = layout
        self.appBundle = appBundle
        self.resources = resources
        self.appVersion = appVersion
        refreshesCommandLineLauncher = layout == .currentUser()
    }

    /// The running app and a data root.
    /// - Parameter dataRoot: Nil for the current user's `~/Library/Application Support/Jerd`.
    ///   Only Debug builds of the app pass another folder, to try the app without user data.
    public init(bundle: Bundle, dataRoot: URL? = nil) {
        self.init(
            layout: dataRoot.map { DataLayout(root: $0) } ?? .currentUser(), appBundle: bundle.bundleURL,
            resources: bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources"),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    /// `Contents/Resources/RuntimePayloads`: the bundled runtime payloads.
    public var payloads: URL { resources.appendingPathComponent("RuntimePayloads", isDirectory: true) }
}
