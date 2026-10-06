import Foundation

/// The Info.plist of a temporary test app. Its Sparkle settings are the `SU*` keys of Jerd's own
/// `Apps/Jerd/Resources/Info.plist`, so the test checks the shipped policy and cannot drift from it.
/// Only the feed URL and the key change, to the loopback feed and the temporary test key.
struct UpdateTestBundle: Sendable {
    static let executableName = "UpdaterTest"
    static let appName = "Updater Test.app"

    var bundleIdentifier: String
    /// `1` for the installed app, `2` for the update.
    var version: String
    var feedURL: URL
    var publicKey: String
    var resultFile: URL
    var refusesFirstQuit: Bool

    /// The Sparkle keys of Jerd's Info.plist.
    /// - Throws: `checkFailed` when the file cannot be read or has no feed URL and key.
    static func sparkleSettings(fromJerdInfoPlist data: Data) throws -> [String: Any] {
        let decoded: Any
        do {
            decoded = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw DevFailure.checkFailed("\(SparkleInfoPlistPolicy.file) is not a property list.")
        }
        guard let dictionary = decoded as? [String: Any] else {
            throw DevFailure.checkFailed("\(SparkleInfoPlistPolicy.file) is not a property list dictionary.")
        }
        let settings = dictionary.filter { $0.key.hasPrefix("SU") }
        guard settings["SUFeedURL"] != nil, settings["SUPublicEDKey"] != nil else {
            throw DevFailure.checkFailed("\(SparkleInfoPlistPolicy.file) has no SUFeedURL and SUPublicEDKey.")
        }
        return settings
    }

    /// The complete Info.plist as an XML property list.
    func infoPlist(sparkleSettings: [String: Any]) throws -> Data {
        var info = sparkleSettings
        let values: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier, "CFBundleName": "Updater Test",
            "CFBundleExecutable": Self.executableName, "CFBundlePackageType": "APPL",
            "CFBundleVersion": version, "CFBundleShortVersionString": version + ".0",
            "LSMinimumSystemVersion": "14.0", "SUFeedURL": feedURL.absoluteString, "SUPublicEDKey": publicKey,
            "NSAppTransportSecurity": ["NSAllowsLocalNetworking": true],
            "TestResultPath": resultFile.path, "TestRefuseFirstQuit": refusesFirstQuit,
        ]
        info.merge(values) { _, new in new }
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    /// Writes `<folder>/Updater Test.app` with the executable and Info.plist and returns the app.
    /// The Sparkle framework is copied and the app is signed by commands of `UpdateFixturePlan`.
    func write(in folder: URL, executable: URL, sparkleSettings: [String: Any]) throws -> URL {
        let app = folder.appending(path: Self.appName, directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: executable, to: macOS.appending(path: Self.executableName))
        try infoPlist(sparkleSettings: sparkleSettings).write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    /// `CFBundleVersion` of an app, or nil when the Info.plist cannot be read.
    static func installedVersion(of app: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: app.appending(path: "Contents/Info.plist").path),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleVersion"] as? String
    }
}
