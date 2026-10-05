import Foundation
import JerdFoundation
import JerdManifest

/// Reads the payloads in `Jerd.app/Contents/Resources/RuntimePayloads`.
///
/// Layout: `runtimes.json` (the pin catalog) and `<group>/<payload ID>/payload-receipt.json` with the
/// payload files. Each receipt must match its pin: ID, kind, release version, artifact digest, and
/// architecture. Folders that no pin names are ignored, so a stale payload is never installed.
public struct BundledPayloadSource: Sendable {
    /// The folder name inside the app resources.
    public static let folderName = "RuntimePayloads"

    public let root: URL
    public let architecture: CPUArchitecture

    public init(root: URL, architecture: CPUArchitecture = .current) {
        self.root = root
        self.architecture = architecture
    }

    /// The catalog of the bundle.
    /// - Throws: `.unavailable` when the bundle is for another architecture.
    public func catalog() throws -> RuntimePinCatalog {
        let data = try BundleFile.read(
            root.appendingPathComponent(RuntimePinCatalog.fileName), limit: RuntimePinCatalog.sizeLimit)
        let catalog = try RuntimePinCatalog.decode(data)
        guard catalog.architecture == architecture else {
            throw JerdError.unavailable("The bundled runtimes do not support this Mac.")
        }
        return catalog
    }

    /// The payloads of one group, in catalog order.
    public func payloads(in group: PayloadGroup) throws -> [BundledPayload] {
        let catalog = try catalog()
        let pins = catalog.pins(in: group)
        guard !pins.isEmpty else { throw JerdError.unavailable("The app has no bundled \(group.rawValue) runtimes.") }
        return try pins.map { try payload(for: $0, catalog: catalog) }
    }

    /// The payload of one pin.
    public func payload(for pin: RuntimePin, catalog: RuntimePinCatalog) throws -> BundledPayload {
        guard let group = pin.group else { throw JerdError.invalid("The pin \(pin.id) is never bundled.") }
        let origin = root.appendingPathComponent(group.rawValue).appendingPathComponent(pin.id, isDirectory: true)
        let bytes = try BundleFile.read(
            origin.appendingPathComponent(PayloadReceipt.fileName), limit: PayloadReceipt.sizeLimit)
        let receipt = try PayloadReceipt.decode(bytes)
        guard receipt.id == pin.id, receipt.kind == pin.kind, receipt.releaseVersion == pin.version,
            receipt.archiveSHA256 == pin.artifactSHA256, receipt.architecture == catalog.architecture
        else { throw JerdError.invalid("The bundled \(pin.kind.title) receipt does not match its pin.") }
        return BundledPayload(pin: pin, receipt: receipt, receiptBytes: bytes, origin: origin)
    }
}
