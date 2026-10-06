import Foundation
import JerdManifest

/// The repository files that a release reads: the version, the deployment target, the changelog, and
/// the committed signed feed.
struct ReleaseSourceFiles: Sendable {
    static let marketingVersion = "MARKETING_VERSION"
    static let buildVersion = "CURRENT_PROJECT_VERSION"
    static let deploymentTarget = "MACOSX_DEPLOYMENT_TARGET"

    let repository: Repository

    func versionFile() throws -> XcconfigFile {
        XcconfigFile(path: "Configuration/Version.xcconfig", text: try text(repository.versionFile))
    }

    /// `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` of `Configuration/Version.xcconfig`.
    func version() throws -> (version: String, build: String) {
        let file = try versionFile()
        return (try file.value(of: Self.marketingVersion), try file.value(of: Self.buildVersion))
    }

    /// The deployment target of every target, from `Configuration/Base.xcconfig`. A release may not
    /// claim an older macOS than the code is built for.
    func deploymentTarget() throws -> ReleaseVersion {
        let file = XcconfigFile(path: "Configuration/Base.xcconfig", text: try text(repository.baseConfiguration))
        let value = try file.value(of: Self.deploymentTarget)
        guard let version = ReleaseVersion(value, parts: 1...3) else {
            throw DevFailure.checkFailed("Configuration/Base.xcconfig has an invalid MACOSX_DEPLOYMENT_TARGET.")
        }
        return version
    }

    func changelog() throws -> String { try text(repository.changelog) }

    /// The committed feed, verified with the official public key only.
    func verifiedFeed() throws -> (data: Data, appcast: Appcast) {
        let data = try read(repository.appcast)
        do {
            return (data, try AppcastVerifier.official().verifiedAppcast(data))
        } catch {
            throw DevFailure.checkFailed("The committed appcast.xml is not validly signed: \(Self.message(error))")
        }
    }

    func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DevFailure.checkFailed("Cannot read \(repository.relativePath(of: url)).")
        }
    }

    func text(_ url: URL) throws -> String { String(decoding: try read(url), as: UTF8.self) }

    static func message(_ error: any Error) -> String { PayloadInventory.message(of: error) }
}
