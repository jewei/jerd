import Foundation
import JerdManifest
import JerdRuntimes

/// `./dev runtimes embed DEST`: the Xcode embed phase calls it to copy the prepared embedded
/// payloads into the app. It verifies every payload receipt (pin, file set, SHA-256, executable
/// flags) before it copies, so an app never contains a payload that its receipt does not describe.
/// Pins that the catalog marks `"embedded": false` (MySQL, PostgreSQL, Mailpit, and RustFS) stay out
/// of the app; the app installs them on demand from the same pins. The XZ library that the RustFS
/// preparation needs goes into `support/xz` with its receipt (`EmbeddedSupport`).
enum RuntimesEmbedStep {
    /// The destination must be the payload folder of an app bundle, because the step removes files in it.
    static let destinationName = BundledPayloadSource.folderName

    /// - Parameter requiresAll: Release: every embedded payload must be present.
    static func run(_ context: DevContext, destination: URL, requiresAll: Bool) async throws {
        guard destination.lastPathComponent == destinationName, destination.path.contains(".app/") else {
            throw DevFailure.usage("The embed destination must be <app>/Contents/Resources/\(destinationName).")
        }
        let start = ContinuousClock.now
        let catalogBytes = try RepositoryPolicy.read("Runtimes/runtimes.json", in: context.repository)
        let catalog = try PayloadInventory.catalog(at: context.repository.runtimeCatalog)
        let entries = EmbeddedPayloads.entries(in: context.repository.payloads, catalog: catalog)
        let payloads = try checked(entries, requiresAll: requiresAll, context: context)
        let support = try checkedSupport(context, catalog: catalog, requiresAll: requiresAll)
        let manager = FileManager.default
        guard !payloads.isEmpty else {
            context.console.warning("No runtime payload is prepared. The app builds without runtimes.")
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            return
        }
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        try removeExtraneous(in: destination, keeping: payloads, support: support.map(\.name))
        for entry in payloads {
            let target = destination.appending(path: entry.group.rawValue).appending(path: entry.pin.id)
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            try await context.runChecked(PayloadSyncPlan.copy(entry.folder, to: target), output: .capture)
        }
        for library in support {
            let target = BundledSupportLibrary.folder(library.name, in: destination)
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            try await context.runChecked(PayloadSyncPlan.copy(library.folder, to: target), output: .capture)
        }
        let catalogFile = destination.appending(path: RuntimePinCatalog.fileName)
        if (try? Data(contentsOf: catalogFile)) != catalogBytes {
            try catalogBytes.write(to: catalogFile)
        }
        let seconds = start.duration(to: .now).formattedSeconds
        let libraries = support.isEmpty ? "" : " and the \(support.map(\.name).joined(separator: ", ")) support library"
        context.console.success("Embedded \(payloads.count) verified runtime payloads\(libraries) in \(seconds).")
    }

    /// The valid entries. Any invalid payload fails; a missing one fails only when all are required.
    static func checked(
        _ entries: [PayloadInventory.Entry], requiresAll: Bool, context: DevContext
    ) throws -> [PayloadInventory.Entry] {
        var invalid: [String] = []
        for entry in entries {
            if case .invalid(let message) = entry.state {
                invalid.append(entry.pin.id)
                context.console.error("\(entry.pin.id): \(message)")
            }
        }
        guard invalid.isEmpty else {
            throw DevFailure.checkFailed(
                "These prepared payloads do not match their receipts: \(invalid.joined(separator: ", ")). "
                    + "Remove them and run ./dev runtimes prepare.")
        }
        let missing = entries.filter { $0.payload == nil }.map(\.pin.id)
        if !missing.isEmpty {
            let list = missing.joined(separator: ", ")
            guard !requiresAll else {
                throw DevFailure.checkFailed(
                    "A Release build needs every embedded runtime payload. Missing: \(list). Run ./dev runtimes prepare."
                )
            }
            if missing.count < entries.count {
                context.console.warning("The app builds without these payloads: \(list).")
            }
        }
        return entries.filter { $0.payload != nil }
    }

    private static func removeExtraneous(
        in destination: URL, keeping payloads: [PayloadInventory.Entry], support: [String]
    ) throws {
        let pins = payloads.map { ($0.pin, $0.group) }
        for path in try PayloadSyncPlan.extraneous(in: destination, keeping: pins, support: support) {
            try FileManager.default.removeItem(at: destination.appending(path: path))
        }
    }
}
