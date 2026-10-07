import Foundation
import JerdManifest

/// The pinned payloads that the app embeds. A release requires, signs, and checks exactly these, and
/// refuses an app that contains any other payload.
enum EmbeddedPayloads {
    /// The embedded pins of `inventory`, in catalog order. The only place that reads the catalog rule.
    static func pins(_ inventory: PayloadInventory) -> [(pin: RuntimePin, group: PayloadGroup)] {
        inventory.pins(in: PayloadGroup.allCases)
    }

    /// The state of each embedded payload in `root`. Other payloads are not read.
    static func entries(in root: URL, catalog: RuntimePinCatalog) -> [PayloadInventory.Entry] {
        let inventory = PayloadInventory(root: root, catalog: catalog)
        return pins(inventory).map { inventory.entry(for: $0.pin, group: $0.group) }
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
        let pins = pins(PayloadInventory(root: root, catalog: catalog))
        let expected = Dictionary(grouping: pins, by: { $0.group.rawValue }).mapValues { Set($0.map(\.pin.id)) }
        let extra = PayloadSyncPlan.extraneous(
            existing: existing, expected: expected, catalogName: RuntimePinCatalog.fileName)
        guard extra.isEmpty else {
            throw DevFailure.checkFailed(
                "The app contains payloads that a release does not embed: \(extra.sorted().joined(separator: ", ")).")
        }
    }
}
