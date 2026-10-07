import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// The pinned payloads in one folder with the bundle layout `<group>/<payload ID>/payload-receipt.json`:
/// `.build/runtimes/payloads` or `Jerd.app/Contents/Resources/RuntimePayloads`.
///
/// It uses the same receipt and pin checks as the app (`BundledPayloadSource`) and the same file
/// comparison as installation (`PayloadScanner`, `PayloadComparison`), so the build, the release, and
/// the app accept exactly the same payloads.
struct PayloadInventory: Sendable {
    /// One pinned payload and what the folder holds for it.
    struct Entry: Sendable {
        enum State: Sendable {
            case missing
            case valid(BundledPayload)
            case invalid(String)
        }

        let pin: RuntimePin
        let group: PayloadGroup
        let folder: URL
        let state: State

        var payload: BundledPayload? {
            if case .valid(let payload) = state { return payload }
            return nil
        }
    }

    let root: URL
    let catalog: RuntimePinCatalog

    /// Reads and validates `Runtimes/runtimes.json`.
    static func catalog(at url: URL) throws -> RuntimePinCatalog {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DevFailure.checkFailed("Cannot read the runtime pin catalog \(url.path).")
        }
        do {
            return try RuntimePinCatalog.decode(data)
        } catch {
            throw DevFailure.checkFailed("The runtime pin catalog is invalid: \(Self.message(of: error))")
        }
    }

    /// The pins that the app bundle embeds, with their groups, in catalog order. The app installs
    /// the other pins (`"embedded": false`) on demand; `./dev runtimes prepare` still prepares all.
    var embeddedPayloads: [(pin: RuntimePin, group: PayloadGroup)] {
        pins(in: PayloadGroup.allCases).filter { $0.pin.isEmbedded }
    }

    /// The state of every embedded payload, in catalog order.
    func embeddedEntries(verifiesFiles: Bool = true) -> [Entry] {
        embeddedPayloads.map { entry(for: $0.pin, group: $0.group, verifiesFiles: verifiesFiles) }
    }

    /// The folder of a pin: `<root>/<group>/<payload ID>`.
    func folder(for pin: RuntimePin, group: PayloadGroup) -> URL {
        root.appending(path: group.rawValue).appending(path: pin.id, directoryHint: .isDirectory)
    }

    /// The bundled pins of `groups`, in catalog order.
    func pins(in groups: [PayloadGroup]) -> [(pin: RuntimePin, group: PayloadGroup)] {
        catalog.pins.compactMap { pin in
            guard let group = pin.group, groups.contains(group) else { return nil }
            return (pin, group)
        }
    }

    /// The state of every pin of `groups`. With `verifiesFiles`, every file digest is checked too.
    func entries(in groups: [PayloadGroup] = PayloadGroup.allCases, verifiesFiles: Bool = true) -> [Entry] {
        pins(in: groups).map { entry(for: $0.pin, group: $0.group, verifiesFiles: verifiesFiles) }
    }

    func entry(for pin: RuntimePin, group: PayloadGroup, verifiesFiles: Bool = true) -> Entry {
        let folder = folder(for: pin, group: group)
        guard FileProbe.presence(at: folder).mayExist else {
            return Entry(pin: pin, group: group, folder: folder, state: .missing)
        }
        do {
            let payload = try BundledPayloadSource(root: root, architecture: catalog.architecture)
                .payload(for: pin, catalog: catalog)
            if verifiesFiles {
                try Self.verifyFiles(of: payload)
            }
            return Entry(pin: pin, group: group, folder: folder, state: .valid(payload))
        } catch {
            return Entry(pin: pin, group: group, folder: folder, state: .invalid(Self.message(of: error)))
        }
    }

    /// The folder holds exactly the receipt files with their SHA-256 and executable flags, plus the
    /// receipt. Finder's `.DS_Store` is ignored, as in installation.
    static func verifyFiles(of payload: BundledPayload) throws {
        let actual = try PayloadScanner.scan(
            payload.origin, ignoring: [PayloadReceipt.fileName], ignoresFinderMetadata: true)
        do {
            try PayloadComparison.requireRecords(payload.receipt.fileRecords, actual: actual)
        } catch let error as JerdError {
            throw JerdError.invalid(
                error.message.replacingOccurrences(of: "The installed runtime changed", with: "Files changed")
                    .replacingOccurrences(of: " Existing files were preserved.", with: ""))
        }
    }

    /// The user message of a JerdKit error, or a description of any other error.
    static func message(of error: any Error) -> String {
        (error as? JerdError)?.message ?? (error as? DevFailure)?.message ?? String(describing: error)
    }
}
