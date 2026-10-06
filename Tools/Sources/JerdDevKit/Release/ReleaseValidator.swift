import Foundation
import JerdFoundation
import JerdManifest

/// `./dev release validate`: checks a whole candidate, as preparation and publication do.
///
/// Every check uses public information: the feed and disk image signatures are verified with the
/// committed public key. Only the extra Keychain check (the private key belongs to that public key)
/// needs the Keychain, and `--public-key-only` leaves it out.
struct ReleaseValidator: Sendable {
    let shell: ReleaseShell
    let layout: CandidateLayout
    let verifier: AppcastVerifier

    @discardableResult
    func run(publicKeyOnly: Bool) async throws -> ReleaseManifest {
        let manifest = try ReleaseManifest.decode(try Data(contentsOf: layout.manifest))
        try Self.checkFiles(manifest, in: layout.root)
        let version = try manifest.releaseVersion
        let build = try manifest.buildNumber
        let minimum = try manifest.minimum
        let info = AppInfoCheck(minimumMacOS: minimum, version: version, build: build)
        try await AppVerifier(shell: shell, team: manifest.teamID, info: info).verify(layout.app, notarized: true)
        let symbols = SymbolArchive(shell: shell)
        try await symbols.verify(app: layout.app, symbols: layout.symbols)
        try await symbols.verifyZip(layout.file(manifest.symbols), app: layout.app)
        let image = layout.file(manifest.dmg)
        try CandidateFeedCheck(verifier: verifier, version: version, build: build, minimumMacOS: minimum)
            .verify(feed: Data(contentsOf: layout.feed), diskImage: image)
        if !publicKeyOnly {
            try await ReleasePreflight.checkSparkleKey(shell)
        }
        try await DiskImageInspection(shell: shell, team: manifest.teamID).verify(image, exportedApp: layout.app)
        shell.console.success("Release signatures, notarization, runtime receipts, symbols, and feed passed.")
        return manifest
    }

    /// Every listed file is a plain name of a regular file in the candidate with its recorded SHA-256.
    static func checkFiles(_ manifest: ReleaseManifest, in root: URL) throws {
        for (name, digest) in manifest.files.sorted(by: { $0.key < $1.key }) {
            guard !name.contains("/"), name != ".", name != ".." else {
                throw DevFailure.checkFailed("release.json lists the unsafe file name \(name).")
            }
            let actual: String
            do {
                actual = try FileDigest.hexSHA256(of: root.appending(path: name))
            } catch {
                throw DevFailure.checkFailed("The release file \(name) is missing or not a regular file.")
            }
            guard actual == digest else { throw DevFailure.checkFailed("The release file \(name) changed.") }
        }
    }
}
