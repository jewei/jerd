import Foundation
import JerdManifest

/// Checks the whole candidate after notarization: the stapled app and its payloads, the symbols and
/// their zip, the feed and the disk image signatures with the committed public key, and the app inside
/// the mounted disk image, which is what users install.
struct ReleaseValidator: Sendable {
    let shell: ReleaseShell
    let layout: CandidateLayout
    let inputs: ReleaseInputs
    let verifier: AppcastVerifier

    func run() async throws {
        let info = AppInfoCheck(minimumMacOS: inputs.minimumMacOS, version: inputs.version, build: inputs.build)
        try await AppVerifier(shell: shell, team: inputs.signing.team, info: info).verify(layout.app, notarized: true)
        let symbols = SymbolArchive(shell: shell)
        try await symbols.verify(app: layout.app, symbols: layout.symbols)
        try await symbols.verifyZip(layout.file(inputs.symbolsName), app: layout.app)
        let image = layout.file(inputs.diskImageName)
        try CandidateFeedCheck(
            verifier: verifier, version: inputs.version, build: inputs.build, minimumMacOS: inputs.minimumMacOS
        ).verify(feed: Data(contentsOf: layout.feed), diskImage: image)
        try await DiskImageInspection(shell: shell, team: inputs.signing.team).verify(image, exportedApp: layout.app)
        shell.console.success("Release signatures, notarization, runtime receipts, symbols, and feed passed.")
    }
}
