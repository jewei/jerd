import Foundation
import JerdManifest

/// Checks the candidate feed with the public key only, so any Mac and CI can run it (fixes spec G
/// 8.1 #25): the feed signature, exactly one item of this build with the release values, and the
/// signature and length of the disk image.
struct CandidateFeedCheck: Sendable {
    let version: ReleaseVersion
    let build: Int
    let minimumMacOS: ReleaseVersion

    func verify(feed: Data, diskImage: URL) throws {
        let verifier = try AppcastVerifier.official()
        let appcast: Appcast
        do {
            appcast = try verifier.verifiedAppcast(feed)
        } catch {
            throw DevFailure.checkFailed(
                "The candidate feed is not validly signed: \(PayloadInventory.message(of: error))")
        }
        let items = appcast.items.filter { $0.bundleVersion == String(build) }
        guard items.count == 1, let item = items.first else {
            throw DevFailure.checkFailed("The candidate feed must have exactly one item of build \(build).")
        }
        guard item.shortVersion == version.text, item.minimumSystemVersion == minimumMacOS.text,
            item.hardwareRequirements == ReleaseNames.architecture
        else { throw DevFailure.checkFailed("The feed item does not match the release version or requirements.") }
        guard item.enclosure.url == ReleaseNames.diskImageURL(version) else {
            throw DevFailure.checkFailed("The feed item does not point to the release disk image.")
        }
        do {
            try verifier.verifyArchive(diskImage, enclosure: item.enclosure)
        } catch {
            throw DevFailure.checkFailed(
                "The disk image does not match the feed: \(PayloadInventory.message(of: error))")
        }
    }
}
