import Foundation
import JerdManifest
import JerdRuntimes

/// `./dev runtimes verify` and `./dev runtimes status`: check every prepared payload against its pin
/// and its receipt, file by file.
enum RuntimesVerifyStep {
    /// Reports each payload and fails when one is missing or invalid, or when a Mach-O file of it
    /// needs a library that the payload does not contain, or, in an embedded payload, a newer macOS
    /// than the deployment target of the app.
    static func verify(_ context: DevContext, groups: [PayloadGroup], verifiesSupport: Bool = true) async throws {
        let inventory = PayloadInventory(
            root: context.repository.payloads,
            catalog: try PayloadInventory.catalog(at: context.repository.runtimeCatalog))
        var failed: [String] = []
        let dependencies = PayloadDependencyCheck(context: context)
        let minimum = try context.repository.runtimeMinimumMacOS()
        for entry in inventory.entries(in: groups) {
            switch entry.state {
            case .valid(let payload):
                let problems = try await dependencies.problems(
                    in: payload, minimumMacOS: entry.pin.isEmbedded ? minimum : nil)
                guard problems.isEmpty else {
                    failed.append(entry.pin.id)
                    for problem in problems { context.console.error("\(entry.pin.id): \(problem)") }
                    context.console.error(
                        "\(entry.pin.id): remove .build/runtimes/payloads/\(entry.group.rawValue)/\(entry.pin.id) "
                            + "and run ./dev runtimes prepare \(entry.group.rawValue).")
                    continue
                }
                context.console.success(
                    "\(entry.pin.id): \(payload.receipt.files.count) files match the receipt; every library resolves"
                        + (entry.pin.isEmbedded ? "; every file runs on macOS \(minimum)." : "."))
            case .missing:
                failed.append(entry.pin.id)
                context.console.error(missingMessage(entry))
            case .invalid(let message):
                failed.append(entry.pin.id)
                context.console.error("\(entry.pin.id): \(message)")
            }
        }
        if verifiesSupport {
            failed += try await verifySupport(context, catalog: inventory.catalog, minimum: minimum)
        }
        guard failed.isEmpty else {
            throw DevFailure.checkFailed("These payloads are missing or invalid: \(failed.joined(separator: ", ")).")
        }
    }

    /// The embedded XZ library: its receipt matches the pin and the deployment target, every file
    /// matches, every library reference resolves, and every file runs on the minimum macOS.
    /// - Returns: The names that failed.
    static func verifySupport(
        _ context: DevContext, catalog: RuntimePinCatalog, minimum: MinimumMacOS
    ) async throws -> [String] {
        var failed: [String] = []
        for name in EmbeddedSupport.names(catalog) {
            let folder = EmbeddedSupport.preparedFolder(name, in: context.repository)
            switch EmbeddedSupport.state(of: name, in: folder, catalog: catalog, deploymentTarget: minimum.description)
            {
            case .valid(let receipt):
                let problems = try await PayloadDependencyCheck(context: context).problems(
                    files: Array(receipt.files.keys), in: folder, minimumMacOS: minimum)
                for problem in problems { context.console.error("support/\(name): \(problem)") }
                if problems.isEmpty {
                    context.console.success(
                        "support/\(name): \(receipt.files.count) files match the receipt; every library resolves; "
                            + "every file runs on macOS \(minimum).")
                } else {
                    failed.append("support/\(name)")
                }
            case .missing:
                failed.append("support/\(name)")
                context.console.error("support/\(name) is not prepared. Run ./dev runtimes prepare xz.")
            case .invalid(let message):
                failed.append("support/\(name)")
                context.console.error("support/\(name): \(message) Run ./dev runtimes prepare xz.")
            }
        }
        return failed
    }

    /// One line for each payload and for the XZ library: group, whether the app embeds it, ID, version,
    /// size, and state.
    static func status(_ context: DevContext) throws {
        let catalog = try PayloadInventory.catalog(at: context.repository.runtimeCatalog)
        let inventory = PayloadInventory(root: context.repository.payloads, catalog: catalog)
        var rows: [[String]] = [["Group", "In app", "Payload", "Version", "Size", "State"]]
        for entry in inventory.entries() {
            let version = versionText(of: entry)
            let size = entry.payload.map { Self.formatted(bytes: FolderSize.bytes(of: $0.origin)) } ?? "-"
            let inApp = entry.pin.isEmbedded ? "yes" : "on demand"
            rows.append([entry.group.rawValue, inApp, entry.pin.id, version, size, stateText(entry.state)])
        }
        if let source = catalog.supportSources["xz"] {
            let folder = context.repository.runtimeSupport.appending(path: "xz")
            let state = stateText(of: EmbeddedSupport.state(of: "xz", in: folder, catalog: catalog))
            rows.append(["support", "yes", "xz-\(source.version)", source.version, sizeText(folder), state])
        }
        context.console.detail(TextTable.render(rows))
    }

    /// The version that the runtime reports, from the receipt. Without a receipt only the catalog version
    /// is known, which for PostgreSQL is the Postgres.app version, so the text names Postgres.app.
    static func versionText(of entry: PayloadInventory.Entry) -> String {
        if let receipt = entry.payload?.receipt { return receipt.version }
        return entry.pin.kind == .postgresql ? "Postgres.app \(entry.pin.version)" : entry.pin.version
    }

    static func missingMessage(_ entry: PayloadInventory.Entry) -> String {
        "\(entry.pin.id) is not prepared. Run ./dev runtimes prepare \(entry.group.rawValue)."
    }

    static func stateText(_ state: PayloadInventory.Entry.State) -> String {
        switch state {
        case .valid: "valid"
        case .missing: "missing"
        case .invalid(let message): "invalid: \(message)"
        }
    }

    static func stateText(of state: EmbeddedSupport.State) -> String {
        switch state {
        case .valid: "valid"
        case .missing: "missing"
        case .invalid(let message): "invalid: \(message)"
        }
    }

    private static func sizeText(_ folder: URL) -> String {
        FileManager.default.fileExists(atPath: folder.path) ? formatted(bytes: FolderSize.bytes(of: folder)) : "-"
    }

    static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
