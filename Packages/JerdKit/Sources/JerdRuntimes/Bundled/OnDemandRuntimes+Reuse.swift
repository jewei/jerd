import Darwin
import Foundation
import JerdFoundation
import JerdManifest

extension OnDemandRuntimes {
    /// A payload folder of the on-demand pin of `kind` that an earlier copy installed from its
    /// bundle, verified file by file, or nil.
    ///
    /// Two forms count: the current `<group folder>/<pin ID>-<16 hex>/` with a `payload-receipt.json`
    /// that matches the pin, and the legacy `<group folder>/<pin ID>/` with a `jerd-receipt.json`
    /// that names the pinned archive digest. A folder that does not match or does not verify is
    /// skipped and kept as it is; Jerd then downloads the pin. Nothing is ever changed or removed.
    ///
    /// Trust: the check proves that the folder holds exactly the files of its own receipt and that
    /// the receipt names the pin. It does not prove where the files came from: the receipt is in the
    /// folder. The boundary is the same user, who owns the data root (the folders must be real
    /// directories of that user inside the data root), as for every installed runtime.
    public func reusablePayload(for kind: RuntimeKind, layout: DataLayout) async throws -> ReusablePayload? {
        try await find(kind, layout: layout, verifiesFiles: true)
    }

    /// True when a folder of the pin of `kind` looks reusable by its receipt, without hashing its
    /// files: the install dialog then says that Jerd reuses it. The install still verifies it.
    public func hasReusablePayload(for kind: RuntimeKind, layout: DataLayout) async throws -> Bool {
        try await find(kind, layout: layout, verifiesFiles: false) != nil
    }

    private func find(_ kind: RuntimeKind, layout: DataLayout, verifiesFiles: Bool) async throws -> ReusablePayload? {
        let catalog = try source.catalog()
        guard let pin = catalog.onDemandPins.first(where: { $0.kind == kind }), let group = pin.group else {
            return nil
        }
        let directory = layout.runtimes.payloadDirectory(for: group)
        // Only a real, owned group folder inside the data root counts: a link never leads reuse
        // to a database binary outside it.
        guard FileProbe.presence(at: directory).mayExist else { return nil }
        do {
            try OwnedDirectory.requireContained(directory, in: layout.root)
        } catch {
            return nil
        }
        let architecture = catalog.architecture
        return try await BlockingWork.run {
            Self.current(pin, in: directory, architecture: architecture, verifiesFiles: verifiesFiles)
                ?? Self.legacy(pin, in: directory, verifiesFiles: verifiesFiles)
        }
    }

    private static func current(
        _ pin: RuntimePin, in directory: URL, architecture: CPUArchitecture, verifiesFiles: Bool
    ) -> ReusablePayload? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.filter({ $0.hasPrefix("\(pin.id)-") }).sorted() {
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            do {
                try requireOwnedFolder(folder)
                let receipt = try PayloadReceipt.decode(
                    AtomicFile.read(
                        folder.appendingPathComponent(PayloadReceipt.fileName), limit: PayloadReceipt.sizeLimit))
                guard receipt.id == pin.id, receipt.kind == pin.kind, receipt.releaseVersion == pin.version,
                    receipt.archiveSHA256 == pin.artifactSHA256, receipt.architecture == architecture,
                    receipt.folderID == name
                else { continue }
                if verifiesFiles { try VerifiedPayloadInstaller.verify(folder, receipt: receipt) }
                return ReusablePayload(id: name, kind: pin.kind, version: receipt.version, directory: folder)
            } catch {
                // Not reusable: the user keeps the folder, and Jerd downloads the pin instead.
                continue
            }
        }
        return nil
    }

    private static func legacy(_ pin: RuntimePin, in directory: URL, verifiesFiles: Bool) -> ReusablePayload? {
        let folder = directory.appendingPathComponent(pin.id, isDirectory: true)
        guard FileProbe.presence(at: folder).mayExist, let group = pin.group else { return nil }
        let format = LegacyPayloadReceipt.Format(group: group)
        do {
            let receipt: LegacyPayloadReceipt
            if verifiesFiles {
                receipt = try LegacyPayloadVerifier.verify(folder, format: format)
            } else {
                try requireOwnedFolder(folder)
                receipt = try LegacyPayloadReceipt.decode(
                    AtomicFile.read(
                        folder.appendingPathComponent(format.fileName), limit: LegacyPayloadReceipt.sizeLimit),
                    format: format)
            }
            guard receipt.archiveSHA256 == pin.artifactSHA256 else { return nil }
            return ReusablePayload(id: pin.id, kind: pin.kind, version: pin.displayVersion, directory: folder)
        } catch {
            return nil
        }
    }

    private static func requireOwnedFolder(_ folder: URL) throws {
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else {
            throw JerdError.invalid("The runtime directory is invalid.")
        }
    }
}
