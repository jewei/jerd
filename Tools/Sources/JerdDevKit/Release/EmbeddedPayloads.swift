import Foundation
import JerdManifest

/// The payload groups that the app embeds. A release requires, signs, and checks exactly these, and
/// refuses an app that contains any other payload.
enum EmbeddedPayloads {
    /// The groups of `catalog` that the app embeds, in catalog order.
    static func groups(_ catalog: RuntimePinCatalog) -> [PayloadGroup] {
        PayloadGroup.allCases
    }

    /// The pinned payloads of the embedded groups in `root`.
    static func entries(in root: URL, catalog: RuntimePinCatalog) -> [PayloadInventory.Entry] {
        PayloadInventory(root: root, catalog: catalog).entries(in: groups(catalog))
    }

    /// `root` holds only the catalog and the folders of the embedded pins, so no payload goes out unsigned.
    static func requireNoOthers(in root: URL, catalog: RuntimePinCatalog) throws {
        let manager = FileManager.default
        var existing: [String: [String]] = [:]
        for name in try manager.contentsOfDirectory(atPath: root.path) {
            let url = root.appending(path: name)
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            existing[name] = isFolder ? try manager.contentsOfDirectory(atPath: url.path) : []
        }
        let inventory = PayloadInventory(root: root, catalog: catalog)
        let pins = inventory.pins(in: groups(catalog))
        let expected = Dictionary(grouping: pins, by: { $0.group.rawValue }).mapValues { Set($0.map(\.pin.id)) }
        let extra = PayloadSyncPlan.extraneous(
            existing: existing, expected: expected, catalogName: RuntimePinCatalog.fileName)
        guard extra.isEmpty else {
            throw DevFailure.checkFailed(
                "The app contains payloads that a release does not embed: \(extra.sorted().joined(separator: ", ")).")
        }
    }
}
