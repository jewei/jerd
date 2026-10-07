import Foundation
import JerdFoundation

/// The pin catalog `Runtimes/runtimes.json`: every bundled payload and every support source.
///
/// The build tool reads it to prepare payloads. The build copies it into the app bundle as
/// `RuntimePayloads/runtimes.json`, where first-launch installation checks each payload receipt
/// against its pin.
public struct RuntimePinCatalog: Codable, Equatable, Sendable {
    /// The catalog file name in the repository folder `Runtimes/` and in `RuntimePayloads/`.
    public static let fileName = "runtimes.json"
    /// A catalog file must be at most this many bytes.
    public static let sizeLimit = 1_000_000
    /// The only schema version.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// The one architecture of every bundled payload.
    public let architecture: CPUArchitecture
    public let pins: [RuntimePin]
    /// Sources that the release tool builds from, for example the XZ library for RustFS.
    public let supportSources: [String: PinnedSupportSource]

    public init(architecture: CPUArchitecture, pins: [RuntimePin], supportSources: [String: PinnedSupportSource] = [:])
    {
        schemaVersion = Self.currentSchemaVersion
        self.architecture = architecture
        self.pins = pins
        self.supportSources = supportSources
    }

    /// Decodes and validates catalog bytes.
    public static func decode(_ data: Data) throws -> RuntimePinCatalog {
        guard data.count <= sizeLimit else { throw invalid("The runtime pin catalog is too large.") }
        let catalog: RuntimePinCatalog
        do {
            catalog = try JSONDecoder().decode(RuntimePinCatalog.self, from: data)
        } catch {
            throw invalid("The runtime pin catalog cannot be read. \(FailureDetail.describe(error))")
        }
        try catalog.validate()
        return catalog
    }

    /// Schema 1, valid pins, unique IDs, and at most one pin of each kind.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw Self.invalid("The runtime pin catalog has an unsupported format version.")
        }
        for pin in pins { try pin.validate() }
        guard Set(pins.map(\.id)).count == pins.count, Set(pins.map(\.kind)).count == pins.count else {
            throw Self.invalid("The runtime pin catalog repeats a payload ID or a runtime kind.")
        }
        for source in supportSources.values { try source.validate() }
    }

    /// The pins whose payloads the build copies into the app, in catalog order. A support source
    /// (`supportSources`) is a build input and is never embedded.
    public var embeddedPins: [RuntimePin] { pins.filter(\.isEmbedded) }

    /// The pins that the app installs on demand, after a user action, in catalog order.
    public var onDemandPins: [RuntimePin] { pins.filter { !$0.isEmbedded } }

    /// The pins of one bootstrap group, in catalog order.
    public func pins(in group: PayloadGroup) -> [RuntimePin] { pins.filter { $0.group == group } }

    /// The pin of a kind, if the catalog has one.
    public func pin(for kind: RuntimeKind) -> RuntimePin? { pins.first { $0.kind == kind } }

    static func invalid(_ message: String) -> JerdError { .invalid(message) }
}
