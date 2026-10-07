import Foundation
import JerdManifest
import JerdRuntimes

extension RuntimeSmokeTest {
    /// The check of the signed XZ library: the prepared RustFS (ad hoc signed, as the app installs it
    /// on demand) runs once from a private folder beside the candidate's Developer ID signed library.
    struct SupportCheck: Equatable, Sendable {
        /// Each file to copy, from the source to the destination.
        var copies: [(source: URL, destination: URL)]
        var command: Command

        static func == (left: SupportCheck, right: SupportCheck) -> Bool {
            left.command == right.command
                && left.copies.map { [$0.source, $0.destination] } == right.copies.map { [$0.source, $0.destination] }
        }
    }

    /// The plan of the XZ check, or nil when the candidate embeds no XZ library or RustFS is embedded.
    /// - Throws: `missingPrerequisite` when the prepared RustFS payload is missing or invalid.
    static func supportCheck(
        appPayloads: URL, prepared: URL, folder: URL
    ) throws -> SupportCheck? {
        let catalog = try PayloadInventory.catalog(at: appPayloads.appending(path: RuntimePinCatalog.fileName))
        guard EmbeddedSupport.names(catalog).contains(BundledSupportLibrary.xzName),
            let pin = catalog.pin(for: .rustfs), !pin.isEmbedded, let group = pin.group
        else { return nil }
        let entry = PayloadInventory(root: prepared, catalog: catalog).entry(for: pin, group: group)
        guard let payload = entry.payload else {
            throw DevFailure.missingPrerequisite(
                "The release loads the signed XZ library with the prepared \(pin.id). Run ./dev runtimes prepare storage."
            )
        }
        let binary = payload.receipt.executable
        let library = BundledSupportLibrary.folder(BundledSupportLibrary.xzName, in: appPayloads)
            .appending(path: XZBuildPlan.libraryName)
        // Beside the library, as `@loader_path/liblzma.5.dylib` of the installed RustFS needs it.
        let executable = folder.appending(path: binary.url(in: payload.origin).lastPathComponent)
        return SupportCheck(
            copies: [
                (binary.url(in: payload.origin), executable),
                (library, folder.appending(path: XZBuildPlan.libraryName)),
            ],
            command: Command(executable: executable, arguments: ["--version"]))
    }

    /// Copies the files of the XZ check into `home` and runs RustFS once. A library that the signed
    /// form cannot load stops the release before anything is public.
    func runSupportCheck(home: URL, environment: [String: String]) async throws {
        let folder = home.appending(path: "xz-check", directoryHint: .isDirectory)
        guard
            let check = try Self.supportCheck(
                appPayloads: layout.appPayloads, prepared: shell.repository.payloads, folder: folder)
        else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for copy in check.copies {
            try FileManager.default.copyItem(at: copy.source, to: copy.destination)
        }
        try await shell.run(
            check.command.executable, check.command.arguments, limit: TimeLimit.probe,
            log: layout.log("runtime-smoke"), environment: environment, directory: home)
        shell.console.success("RustFS loaded the signed XZ library of the app.")
    }
}
