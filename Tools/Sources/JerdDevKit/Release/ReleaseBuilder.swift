import Foundation
import JerdFoundation

/// The local steps of a release: archive, payload and app signatures, notarization of the app and the
/// disk image, the Sparkle signatures, and the final validation. They write only the candidate folder,
/// change no tracked file, and publish nothing.
struct ReleaseBuilder: Sendable {
    let environment: ReleaseEnvironment
    let inputs: ReleaseInputs
    let source: ReleaseSource
    let layout: CandidateLayout

    var shell: ReleaseShell { environment.shell }

    var steps: [ReleaseStep] {
        [
            ReleaseStep("Archive the app") { try await archive() },
            ReleaseStep("Sign and check the app") { try await signApp() },
            ReleaseStep("Notarize the app") { try await notarizeApp() },
            ReleaseStep("Build and notarize the disk image") { try await buildDiskImage() },
            ReleaseStep("Sign the disk image and the feed") { try await signFeed() },
            ReleaseStep("Validate the candidate") { try await validate() },
        ]
    }

    /// A new private candidate folder, the source feed, the notes, and the archived app.
    func archive() async throws {
        try makeFolder()
        environment.console.detail("Candidate folder: \(environment.repository.relativePath(of: layout.root))")
        try source.feed.write(to: layout.sourceFeed)
        try Data(ReleaseNotes.file(notes: source.notes, minimumMacOS: inputs.minimumMacOS).utf8).write(to: layout.notes)
        try await AppArchiver(shell: shell, inputs: inputs, layout: layout).run()
    }

    /// Signs every embedded payload, Sparkle, and the app, checks every signature, and zips the symbols.
    func signApp() async throws {
        _ = try await PayloadSigner(shell: shell, signing: inputs.signing, layout: layout).run()
        try await AppSigner(shell: shell, signing: inputs.signing).run(app: layout.app)
        let info = AppInfoCheck(minimumMacOS: inputs.minimumMacOS, version: inputs.version, build: inputs.build)
        try await AppVerifier(shell: shell, team: inputs.signing.team, info: info).verify(layout.app, notarized: false)
        try await SymbolArchive(shell: shell).create(layout: layout, zip: layout.file(inputs.symbolsName))
    }

    func notarizeApp() async throws {
        try await shell.run(
            SystemProgram.ditto,
            ["-c", "-k", "--sequesterRsrc", "--keepParent", layout.app.path, layout.appSubmission.path],
            limit: TimeLimit.appCopy)
        _ = try await notarizer.notarize(layout.appSubmission, name: "app", staple: layout.app)
    }

    func buildDiskImage() async throws {
        _ = try await DiskImageBuilder(shell: shell, signing: inputs.signing, layout: layout)
            .build(layout.file(inputs.diskImageName), notarizer: notarizer)
    }

    /// The Sparkle signature of the disk image and the signed candidate feed with one new item.
    func signFeed() async throws {
        let image = layout.file(inputs.diskImageName)
        let size = try FileManager.default.attributesOfItem(atPath: image.path)[.size] as? NSNumber
        let item = AppcastWriter.Item(
            version: inputs.version, build: inputs.build, minimumMacOS: inputs.minimumMacOS, notes: source.notes,
            publishedAt: environment.clock.now(), archiveLength: size?.int64Value ?? 0, archiveSignature: "")
        let check = CandidateFeedCheck(
            verifier: environment.verifier, version: inputs.version, build: inputs.build,
            minimumMacOS: inputs.minimumMacOS)
        try await FeedSigner(shell: shell, layout: layout).run(item: item, diskImage: image, check: check)
    }

    /// Every check again on the final files, and the source commit and tree are unchanged.
    func validate() async throws {
        try await ReleaseValidator(shell: shell, layout: layout, inputs: inputs, verifier: environment.verifier).run()
        try await SourceCheck(shell: shell).requireClean(at: source.commit)
    }

    private var notarizer: Notarizer { Notarizer(shell: shell, credentials: inputs.notary, layout: layout) }

    /// Replaces an earlier candidate of the same version and build with an empty folder of mode 0700.
    func makeFolder() throws {
        let manager = FileManager.default
        if FileProbe.presence(at: layout.root).mayExist {
            guard CleanPlan.isSafeToRemove(layout.root, repository: environment.repository) else {
                throw DevFailure.checkFailed("\(layout.root.path) is not a build folder. It was not removed.")
            }
            try manager.removeItem(at: layout.root)
        }
        try manager.createDirectory(at: layout.root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(
            at: layout.root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
}
