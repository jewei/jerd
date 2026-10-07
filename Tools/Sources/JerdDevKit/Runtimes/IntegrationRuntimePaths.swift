import Foundation
import JerdManifest
import JerdRuntimes

/// Computes the `JERD_*` runtime paths of the integration tests from the payload receipts, so that no
/// file name (for example a PHP version) is written in the tool.
///
/// `./dev test --integration` uses the prepared payloads. Every payload is verified file by file
/// before a test runs it.
struct IntegrationRuntimePaths: Sendable {
    let inventory: PayloadInventory
    /// The folder for the database index: `<indexRoot>/database/pins.json` and one link per payload.
    let indexRoot: URL
    /// Where the pins that the app installs on demand come from, when `inventory` is an app that does
    /// not embed them: `./dev release prepare` passes `.build/runtimes/payloads`. Nil: `inventory`.
    var onDemandInventory: PayloadInventory? = nil

    /// The path variables of `group`.
    /// - Throws: `missingPrerequisite` when a payload is not prepared, `checkFailed` when one is invalid.
    func variables(for group: IntegrationGroup) throws -> [String: String] {
        switch group {
        case .web:
            let php = try payload(.php)
            guard let fpm = php.receipt.secondaryExecutable else {
                throw DevFailure.checkFailed("The PHP payload \(php.pin.id) records no PHP-FPM executable.")
            }
            return [
                "JERD_PHP_CLI": php.receipt.executable.url(in: php.origin).path,
                "JERD_PHP_FPM": fpm.url(in: php.origin).path,
                "JERD_CADDY": try executable(.caddy),
            ]
        case .database:
            return ["JERD_DATABASE_RUNTIMES": try databaseIndex().path]
        case .mail:
            return ["JERD_MAIL_RUNTIME": try payload(.mailpit).origin.path]
        case .storage:
            return ["JERD_STORAGE_RUNTIME": try payload(.rustfs).origin.path]
        }
    }

    private func executable(_ kind: RuntimeKind) throws -> String {
        let payload = try payload(kind)
        return payload.receipt.executable.url(in: payload.origin).path
    }

    private func payload(_ kind: RuntimeKind) throws -> BundledPayload {
        guard let pin = inventory.catalog.pin(for: kind), let group = pin.group else {
            throw DevFailure.checkFailed("The runtime pin catalog has no \(kind.rawValue) pin.")
        }
        let source = pin.isEmbedded ? inventory : (onDemandInventory ?? inventory)
        let entry = source.entry(for: pin, group: group)
        switch entry.state {
        case .valid(let payload):
            return payload
        case .missing:
            throw DevFailure.missingPrerequisite(
                "The \(pin.id) payload is missing in \(source.root.path). Run ./dev runtimes prepare \(group.rawValue)."
            )
        case .invalid(let message):
            throw DevFailure.checkFailed("The \(pin.id) payload is invalid: \(message)")
        }
    }

    /// The database tests read `<folder>/pins.json` (`artifacts` with `id`, `engine`, and `version`) and
    /// run `<folder>/<id>`. This folder holds that index and a symbolic link to each verified payload,
    /// so the payload folders themselves stay unchanged.
    private func databaseIndex() throws -> URL {
        var artifacts: [[String: String]] = []
        var links: [(name: String, target: URL)] = []
        for kind in PayloadGroup.database.kinds {
            let payload = try payload(kind)
            artifacts.append(["id": payload.pin.id, "engine": kind.rawValue, "version": payload.receipt.version])
            links.append((payload.pin.id, payload.origin))
        }
        let folder = indexRoot.appending(path: PayloadGroup.database.rawValue, directoryHint: .isDirectory)
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) {
            try manager.removeItem(at: folder)
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for link in links {
            try manager.createSymbolicLink(at: folder.appending(path: link.name), withDestinationURL: link.target)
        }
        let index = try JSONSerialization.data(
            withJSONObject: ["artifacts": artifacts], options: [.prettyPrinted, .sortedKeys])
        try index.write(to: folder.appending(path: "pins.json"))
        return folder
    }
}
