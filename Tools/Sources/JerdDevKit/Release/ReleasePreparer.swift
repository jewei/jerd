import Foundation
import JerdFoundation

/// `./dev release prepare`: builds, signs, tests, notarizes, and validates a private candidate.
/// Nothing becomes public. The candidate records each result in `state.json`; a failure ends in the
/// terminal `prepareFailed` and keeps every log.
struct ReleasePreparer: Sendable {
    /// The facts of the source commit that the candidate uses.
    struct Source: Sendable {
        var commit: String
        var notes: String
        var feed: Data
    }

    let environment: ReleaseEnvironment
    let inputs: ReleaseInputs

    var shell: ReleaseShell { environment.shell }

    @discardableResult
    func run() async throws -> CandidateLayout {
        let source = try await checkSource()
        try await ReleasePreflight(shell: shell, inputs: inputs).run()
        let layout = try CandidateStore(releases: environment.repository.releases)
            .create(version: inputs.version, build: inputs.build)
        var state = ReleaseState(startedAt: environment.clock.now())
        try CandidateStore.save(state, to: layout)
        environment.console.detail(
            "Prepare the private candidate \(environment.repository.relativePath(of: layout.root)).")
        do {
            try await buildApp(layout, source: source)
            try await package(layout, source: source)
            try await ReleaseValidator(shell: shell, layout: layout, verifier: environment.verifier).run(
                publicKeyOnly: false)
            try state.advance(to: .prepared, at: environment.clock.now())
            try CandidateStore.save(state, to: layout)
        } catch {
            state.failure = PayloadInventory.message(of: error)
            try? state.advance(to: .prepareFailed, at: environment.clock.now())
            try? CandidateStore.save(state, to: layout)
            throw error
        }
        environment.console.success("Private candidate ready: \(environment.repository.relativePath(of: layout.root))")
        return layout
    }

    /// The clean source commit sets this version, has its notes, and follows every published release.
    func checkSource() async throws -> Source {
        let commit = try await SourceCheck(shell: shell).requireClean()
        let files = ReleaseSourceFiles(repository: environment.repository, verifier: environment.verifier)
        try VersionRules.checkSource(version: inputs.version, build: inputs.build, file: try files.version())
        let target = try files.deploymentTarget()
        guard inputs.minimumMacOS >= target else {
            throw DevFailure.usage("--minimum-macos must be \(target) or later, the deployment target of the code.")
        }
        let notes = try ReleaseNotes.section(for: inputs.version.text, in: try files.changelog())
        let feed = try files.verifiedFeed()
        try VersionRules.checkFeed(version: inputs.version, build: inputs.build, items: feed.appcast.items)
        return Source(commit: commit, notes: notes, feed: feed.data)
    }

    /// Archive, payload signatures, app signatures, checks, symbols, and the runtime tests.
    func buildApp(_ layout: CandidateLayout, source: Source) async throws {
        try source.feed.write(to: layout.sourceFeed)
        try Data(ReleaseNotes.file(notes: source.notes, minimumMacOS: inputs.minimumMacOS).utf8).write(to: layout.notes)
        try await AppArchiver(shell: shell, inputs: inputs, layout: layout).run()
        _ = try await PayloadSigner(shell: shell, signing: inputs.signing, layout: layout).run()
        try await AppSigner(shell: shell, signing: inputs.signing).run(app: layout.app)
        let info = AppInfoCheck(minimumMacOS: inputs.minimumMacOS, version: inputs.version, build: inputs.build)
        try await AppVerifier(shell: shell, team: inputs.signing.team, info: info).verify(layout.app, notarized: false)
        try await SymbolArchive(shell: shell).create(layout: layout, zip: layout.file(symbolsName))
        try await ReleaseRuntimeTests(shell: shell, layout: layout).run()
        try await SourceCheck(shell: shell).requireClean(at: source.commit)
    }

    /// Notarized app and disk image, the signed feed, and the manifest.
    func package(_ layout: CandidateLayout, source: Source) async throws {
        let notarizer = Notarizer(shell: shell, credentials: inputs.notary, layout: layout)
        try await shell.run(
            SystemProgram.ditto,
            ["-c", "-k", "--sequesterRsrc", "--keepParent", layout.app.path, layout.appSubmission.path],
            limit: TimeLimit.appCopy)
        let appSubmission = try await notarizer.notarize(layout.appSubmission, name: "app", staple: layout.app)
        let image = layout.file(ReleaseNames.diskImage(inputs.version))
        let imageSubmission = try await DiskImageBuilder(shell: shell, signing: inputs.signing, layout: layout)
            .build(image, notarizer: notarizer)
        let size = try FileManager.default.attributesOfItem(atPath: image.path)[.size] as? NSNumber
        let item = AppcastWriter.Item(
            version: inputs.version, build: inputs.build, minimumMacOS: inputs.minimumMacOS, notes: source.notes,
            publishedAt: environment.clock.now(), archiveLength: size?.int64Value ?? 0, archiveSignature: "")
        let check = CandidateFeedCheck(
            verifier: environment.verifier, version: inputs.version, build: inputs.build,
            minimumMacOS: inputs.minimumMacOS)
        try await FeedSigner(shell: shell, layout: layout).run(item: item, diskImage: image, check: check)
        try await SourceCheck(shell: shell).requireClean(at: source.commit)
        let manifest = try await manifest(
            layout, source: source, notarization: .init(app: appSubmission, dmg: imageSubmission))
        try manifest.encoded().write(to: layout.manifest)
    }

    func manifest(
        _ layout: CandidateLayout, source: Source, notarization: ReleaseManifest.Notarization
    ) async throws -> ReleaseManifest {
        let image = ReleaseNames.diskImage(inputs.version)
        var files: [String: String] = [:]
        for name in [image, symbolsName, CandidateLayout.feedName, CandidateLayout.notesName] {
            files[name] = try FileDigest.hexSHA256(of: layout.file(name))
        }
        let system = try await shell.output(SystemProgram.swVers, ["-productVersion"], limit: TimeLimit.probe)
        return ReleaseManifest(
            version: inputs.version.text, build: String(inputs.build), teamID: inputs.signing.team,
            minimumMacOS: inputs.minimumMacOS.text, sourceCommit: source.commit,
            sourceFeedSHA256: FileDigest.hexSHA256(of: source.feed), dmg: image, symbols: symbolsName, files: files,
            notarization: notarization, testedSystem: system)
    }

    private var symbolsName: String { ReleaseNames.symbols(inputs.version, build: inputs.build) }
}
