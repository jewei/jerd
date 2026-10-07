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
    /// The settings of each payload group (`development`, `database`, …) and each support source
    /// (`xz`). Catalogs of older builds have none: every payload group is embedded then.
    public let groups: [String: PayloadGroupSettings]?

    public init(
        architecture: CPUArchitecture, pins: [RuntimePin], supportSources: [String: PinnedSupportSource] = [:],
        groups: [String: PayloadGroupSettings]? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.architecture = architecture
        self.pins = pins
        self.supportSources = supportSources
        self.groups = groups
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
        try validateGroups()
    }

    /// True when the app bundle embeds the payloads of `group`.
    public func isEmbedded(_ group: PayloadGroup) -> Bool {
        groups?[group.rawValue]?.embedded ?? true
    }

    /// The groups that the build copies into the app, in `PayloadGroup` order.
    public var embeddedGroups: [PayloadGroup] { PayloadGroup.allCases.filter(isEmbedded) }

    /// The pins that the app installs on demand: every pin of a group that is not embedded.
    public var onDemandPins: [RuntimePin] {
        pins.filter { pin in pin.group.map { !isEmbedded($0) } ?? false }
    }

    /// Every payload group and support source has one entry, and nothing else. A support
    /// source is a build input, so it is never embedded.
    private func validateGroups() throws {
        guard let groups else { return }
        let expected = Set(PayloadGroup.allCases.map(\.rawValue)).union(supportSources.keys)
        guard Set(groups.keys) == expected else {
            throw Self.invalid("The runtime pin catalog must list each payload group and support source once.")
        }
        guard supportSources.keys.allSatisfy({ groups[$0]?.embedded == false }) else {
            throw Self.invalid("A support source of the runtime pin catalog is a build input and is never embedded.")
        }
    }

    /// The pins of one bootstrap group, in catalog order.
    public func pins(in group: PayloadGroup) -> [RuntimePin] { pins.filter { $0.group == group } }

    /// The pin of a kind, if the catalog has one.
    public func pin(for kind: RuntimeKind) -> RuntimePin? { pins.first { $0.kind == kind } }

    static func invalid(_ message: String) -> JerdError { .invalid(message) }
}
