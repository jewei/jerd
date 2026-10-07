import Foundation
import JerdManifest
import JerdRuntimes

/// `./dev runtimes verify` and `./dev runtimes status`: check every prepared payload against its pin
/// and its receipt, file by file.
enum RuntimesVerifyStep {
    /// Reports each payload and fails when one is missing or invalid.
    static func verify(_ context: DevContext, groups: [PayloadGroup]) throws {
        let inventory = PayloadInventory(
            root: context.repository.payloads,
            catalog: try PayloadInventory.catalog(at: context.repository.runtimeCatalog))
        var failed: [String] = []
        for entry in inventory.entries(in: groups) {
            switch entry.state {
            case .valid(let payload):
                context.console.success("\(entry.pin.id): \(payload.receipt.files.count) files match the receipt.")
            case .missing:
                failed.append(entry.pin.id)
                context.console.error(missingMessage(entry))
            case .invalid(let message):
                failed.append(entry.pin.id)
                context.console.error("\(entry.pin.id): \(message)")
            }
        }
        guard failed.isEmpty else {
            throw DevFailure.checkFailed("These payloads are missing or invalid: \(failed.joined(separator: ", ")).")
        }
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
            rows.append(["support", "no", "xz-\(source.version)", source.version, sizeText(folder), xzState(folder)])
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

    private static func xzState(_ folder: URL) -> String {
        do {
            guard let receipt = try SupportReceipt.read(from: folder) else { return "missing" }
            try receipt.verify(in: folder)
            return "valid"
        } catch {
            return "invalid: \(PayloadInventory.message(of: error))"
        }
    }

    private static func sizeText(_ folder: URL) -> String {
        FileManager.default.fileExists(atPath: folder.path) ? formatted(bytes: FolderSize.bytes(of: folder)) : "-"
    }

    static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
