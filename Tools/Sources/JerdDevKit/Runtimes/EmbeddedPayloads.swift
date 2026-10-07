import Foundation
import JerdManifest

/// The pinned payloads that the app embeds. The Xcode embed phase copies exactly these into the app,
/// and a release requires, signs, and checks exactly these and refuses an app with any other payload.
enum EmbeddedPayloads {
    /// The embedded pins of `inventory`, in catalog order. The build and the release both select
    /// through this function, so they always agree.
    static func pins(_ inventory: PayloadInventory) -> [(pin: RuntimePin, group: PayloadGroup)] {
        inventory.embeddedPayloads
    }

    /// The state of each embedded payload in `root`. Other payloads are not read.
    static func entries(in root: URL, catalog: RuntimePinCatalog) -> [PayloadInventory.Entry] {
        let inventory = PayloadInventory(root: root, catalog: catalog)
        return pins(inventory).map { inventory.entry(for: $0.pin, group: $0.group) }
    }

    /// `root` holds only the catalog, the folders of the embedded pins, and the embedded support
    /// folders, so no payload goes out unsigned.
    static func requireNoOthers(in root: URL, catalog: RuntimePinCatalog) throws {
        let extra = try PayloadSyncPlan.extraneous(
            in: root, keeping: pins(PayloadInventory(root: root, catalog: catalog)),
            support: EmbeddedSupport.names(catalog))
        guard extra.isEmpty else {
            throw DevFailure.checkFailed(
                "The app contains payloads that a release does not embed: \(extra.joined(separator: ", ")).")
        }
    }
}
