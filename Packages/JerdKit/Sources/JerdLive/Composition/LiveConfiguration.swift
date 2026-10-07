import CryptoKit
import Foundation
import JerdFoundation
import JerdRuntimes

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
    /// `LSMinimumSystemVersion` of the app: a runtime that the app builds from source must run on
    /// the same Macs as the app.
    public let minimumMacOS: MinimumMacOS
    /// True when the launch replaces an outdated command-line launcher in `bin/`. It starts true
    /// only for the current user's data root, because the launcher in `bin/` is the user's.
    public var refreshesCommandLineLauncher: Bool

    public init(
        layout: DataLayout, appBundle: URL, resources: URL, appVersion: String?,
        minimumMacOS: MinimumMacOS = .jerdKitMinimum
    ) {
        self.layout = layout
        self.appBundle = appBundle
        self.resources = resources
        self.appVersion = appVersion
        self.minimumMacOS = minimumMacOS
        refreshesCommandLineLauncher = layout == .currentUser()
    }

    /// The running app and a data root.
    /// - Parameter dataRoot: Nil for the current user's `~/Library/Application Support/Jerd`.
    ///   Only Debug builds of the app pass another folder, to try the app without user data.
    public init(bundle: Bundle, dataRoot: URL? = nil) {
        self.init(
            layout: dataRoot.map { DataLayout(root: $0) } ?? .currentUser(), appBundle: bundle.bundleURL,
            resources: bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources"),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            minimumMacOS: .of(bundle))
    }

    /// The defaults domain for Jerd's own keys (`showMenuBar`, `showDock`, `appIcon`): nil for the
    /// user's data root, which uses the app's `dev.jerd.app` domain. Another data root gets its
    /// own domain, so a Debug run on an empty folder sees a true first launch and never changes
    /// the user's menu bar, Dock, or icon choice.
    public var defaultsSuiteName: String? {
        layout == .currentUser() ? nil : Self.defaultsSuiteName(forDataRoot: layout.root)
    }

    /// The defaults that `LiveApp` uses: the standard domain, or the domain of another data root.
    public func makeDefaults() -> UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// `dev.jerd.app.debug.<16 hex digits of the SHA-256 of the root path>`: one stable domain
    /// per folder.
    package static func defaultsSuiteName(forDataRoot root: URL) -> String {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path(percentEncoded: false).utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "dev.jerd.app.debug.\(hex)"
    }

    /// `Contents/Resources/RuntimePayloads`: the bundled runtime payloads.
    public var payloads: URL { resources.appendingPathComponent("RuntimePayloads", isDirectory: true) }
}
