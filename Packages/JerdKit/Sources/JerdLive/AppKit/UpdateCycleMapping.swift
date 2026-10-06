import Foundation
import JerdManifest
import JerdUI

/// The pure rules of the Sparkle adapter in the app target, kept here so they have tests.
/// Sparkle itself is linked only into the app.
public enum UpdateCycleMapping {
    /// Sparkle's error domain and the codes that the About page tells apart.
    public static let sparkleErrorDomain = "SUSparkleErrorDomain"
    public static let noUpdateErrorCode = 1001
    public static let installationCanceledErrorCode = 4007

    /// How an update cycle ended, from Sparkle's error.
    public static func result(for error: (any Error)?) -> AppUpdateCycleResult {
        guard let error else { return .completed }
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (sparkleErrorDomain, noUpdateErrorCode):
            return .noUpdate
        case (sparkleErrorDomain, installationCanceledErrorCode), (NSCocoaErrorDomain, NSUserCancelledError):
            return .cancelled
        default:
            return .failed(nsError.localizedDescription)
        }
    }

    /// The error that refuses a check while Jerd quits. It is a user cancellation, so Sparkle
    /// shows no failure for it.
    @MainActor
    public static func stoppingError() -> NSError {
        NSError(
            domain: NSCocoaErrorDomain, code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: AppUpdatesModel.stoppingMessage])
    }

    /// The validated feed of the bundle (`SUFeedURL`, `SUPublicEDKey`). A user-defaults feed can
    /// never redirect the updater, because the adapter returns this value to Sparkle.
    /// - Throws: When a value is missing, malformed, or not the official one.
    public static func feedURL(in bundle: Bundle) throws -> String {
        let settings = try AppUpdateSettings(
            feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        return settings.feedURL.absoluteString
    }
}
