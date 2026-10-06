import Foundation
import JerdManifest

/// The Info.plist rules of a release app. Pure: it reads a decoded dictionary.
///
/// The app has the official bundle ID, feed URL, and key, every Sparkle key of the policy (also the
/// automatic-check, automatic-update, and profiling keys; fixes spec G 8.1 #17), the explicit minimum
/// macOS version, and the release version.
struct AppInfoCheck: Sendable {
    let minimumMacOS: ReleaseVersion
    let version: ReleaseVersion
    let build: Int

    func check(_ info: [String: Any]) throws {
        guard info["CFBundleIdentifier"] as? String == ReleaseNames.appIdentifier else {
            throw failure("The app has the wrong bundle identifier.")
        }
        do {
            _ = try AppUpdateSettings(
                feedURL: info["SUFeedURL"] as? String, publicKey: info["SUPublicEDKey"] as? String)
        } catch {
            throw failure(PayloadInventory.message(of: error))
        }
        for (key, required) in SparkleInfoPlistPolicy.requiredValues
        where !key.hasPrefix("SUFeed") && key != "SUPublicEDKey" {
            guard info[key].flatMap(SparkleInfoPlistPolicy.value(of:)) == required else {
                throw failure("The app's \(key) must be \(required).")
            }
        }
        guard info["LSMinimumSystemVersion"] as? String == minimumMacOS.text else {
            throw failure("The app's LSMinimumSystemVersion must be \(minimumMacOS).")
        }
        guard info["CFBundleShortVersionString"] as? String == version.text,
            info["CFBundleVersion"] as? String == String(build)
        else { throw failure("The app's version must be \(version) (\(build)).") }
    }

    static func read(_ app: URL) throws -> [String: Any] {
        let file = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: file),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw DevFailure.checkFailed("Cannot read the Info.plist of \(app.lastPathComponent).") }
        return info
    }

    private func failure(_ message: String) -> DevFailure { DevFailure.checkFailed(message) }
}
