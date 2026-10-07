import ArgumentParser
import JerdRuntimes

/// `./dev runtimes prepare [GROUP...]`: downloads, verifies, and prepares the pinned payloads.
struct RuntimesPrepareCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Download, verify, and prepare the pinned payloads. Default: every group.",
        discussion: """
            Groups: development (PHP, Caddy, Composer, Laravel installer), database (MySQL, PostgreSQL, \
            Redis), mail (Mailpit), storage (RustFS), and xz (the XZ library that RustFS needs; storage \
            selects it). MySQL is checked with Oracle's pinned OpenPGP key in Swift, so GnuPG is not needed. \
            Redis and XZ build with the Xcode compiler. An earlier payload of the same pin is verified and \
            kept. Groups continue after a failure; the summary lists each result.
            """)

    @Argument(help: ArgumentHelp("Groups to prepare: development, database, mail, storage, xz.", valueName: "group"))
    var groups: [String] = []

    @OptionGroup var options: GlobalOptions

    func validate() throws {
        do {
            _ = try RuntimeSelection.parse(groups)
        } catch let failure as DevFailure {
            throw ValidationError(failure.message)
        }
    }

    func run() async throws {
        let context = try options.context()
        let selection = try RuntimeSelection.parse(groups)
        let catalog = try PayloadInventory.catalog(at: context.repository.runtimeCatalog)
        let step = RuntimesPrepareStep.live(context, catalog: catalog)
        try await step.checkPrerequisites(catalog: catalog, selection: selection)
        var sequence = StepSequence(console: context.console)
        var lzma: SupportLibrary?
        if selection.buildsXZ {
            await sequence.run("XZ support library") { lzma = try await step.prepareXZ(catalog: catalog) }
        }
        for group in selection.groups {
            await sequence.run("Prepare \(group.rawValue) runtimes") {
                try await step.prepare(group, catalog: catalog, lzma: lzma)
            }
        }
        try sequence.finish()
    }
}
