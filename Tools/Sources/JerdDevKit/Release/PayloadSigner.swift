import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// Signs every Mach-O file of the payloads inside the exported app and records the new digests.
///
/// All payloads are verified before any file changes. Each receipt then gets the new SHA-256 of every
/// signed file through `PayloadReceipt.replacingFiles`, and a signing record with the team and the
/// digest of the prepared receipt. The new digests give a new payload folder ID, so a signed payload
/// installs beside an earlier one. The XZ library of RustFS is signed here too.
struct PayloadSigner: Sendable {
    /// What one payload got.
    struct Report: Equatable, Sendable {
        var payloadID: String
        var signedFiles: Int
    }

    let shell: ReleaseShell
    let signing: SigningIdentity
    let layout: CandidateLayout

    func run() async throws -> [Report] {
        let payloads = try Self.verifiedPayloads(in: layout.appPayloads)
        var reports: [Report] = []
        for payload in payloads {
            let count = try await sign(payload)
            shell.console.detail("Signed \(payload.pin.id): \(count) files.")
            reports.append(Report(payloadID: payload.pin.id, signedFiles: count))
        }
        let resigned = try Self.verifiedPayloads(in: layout.appPayloads)
        guard resigned.allSatisfy({ $0.receipt.signing?.teamID == signing.team }) else {
            throw DevFailure.checkFailed("A signed payload receipt has no signing record.")
        }
        return reports
    }

    /// Every embedded payload of the bundle, each verified file by file.
    static func verifiedPayloads(in root: URL) throws -> [BundledPayload] {
        let catalog = try PayloadInventory.catalog(at: root.appending(path: RuntimePinCatalog.fileName))
        let inventory = PayloadInventory(root: root, catalog: catalog)
        return try inventory.embeddedEntries().map { entry in
            switch entry.state {
            case .valid(let payload): return payload
            case .missing: throw DevFailure.checkFailed("The app has no \(entry.pin.id) payload.")
            case .invalid(let message): throw DevFailure.checkFailed("The \(entry.pin.id) payload: \(message)")
            }
        }
    }

    func sign(_ payload: BundledPayload) async throws -> Int {
        let signer = BinarySigner(shell: shell, signing: signing, entitlementsFolder: layout.entitlements)
        let receipt = payload.receipt
        let jit: Set<RelativePath> =
            receipt.kind == .php ? Set([receipt.executable] + [receipt.secondaryExecutable].compactMap { $0 }) : []
        var records = receipt.fileRecords
        var count = 0
        for (path, record) in records.sorted(by: { $0.key < $1.key }) {
            let file = path.url(in: payload.origin)
            guard MachOFile.isMachO(file) else { continue }
            try await signer.sign(file, identifier: file.lastPathComponent, isPHP: jit.contains(path))
            records[path] = PayloadFileRecord(sha256: try FileDigest.hexSHA256(of: file), executable: record.executable)
            count += 1
        }
        let signed = receipt.replacingFiles(
            records,
            signing: PayloadSigning(
                teamID: signing.team, sourceReceiptSHA256: FileDigest.hexSHA256(of: payload.receiptBytes)))
        try AtomicFile.write(
            try signed.encoded(), to: payload.origin.appending(path: PayloadReceipt.fileName), durability: .standard)
        return count
    }
}
