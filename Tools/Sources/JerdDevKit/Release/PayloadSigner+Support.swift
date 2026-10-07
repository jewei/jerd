import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

extension PayloadSigner {
    /// Signs every Mach-O file of each embedded support folder (the XZ library) and records the new
    /// digests with a signing record, as for the payloads. The app checks the library against this
    /// receipt before it copies it into an installed RustFS.
    func signSupport() async throws -> [Report] {
        let root = layout.appPayloads
        let catalog = try PayloadInventory.catalog(at: root.appending(path: RuntimePinCatalog.fileName))
        let signer = BinarySigner(shell: shell, signing: signing, entitlementsFolder: layout.entitlements)
        var reports: [Report] = []
        for library in try EmbeddedSupport.verified(in: root, catalog: catalog) {
            let receiptFile = library.folder.appending(path: SupportReceipt.fileName)
            let source = try Data(contentsOf: receiptFile)
            var files = library.receipt.files
            var count = 0
            for name in files.keys.sorted() {
                let file = library.folder.appending(path: name)
                guard MachOFile.isMachO(file) else { continue }
                try await signer.sign(file, identifier: name, isPHP: false)
                files[name] = try FileDigest.hexSHA256(of: file)
                count += 1
            }
            let signed = library.receipt.replacingFiles(
                files,
                signing: PayloadSigning(teamID: signing.team, sourceReceiptSHA256: FileDigest.hexSHA256(of: source)))
            try AtomicFile.write(try signed.encoded(), to: receiptFile, durability: .standard)
            shell.console.detail("Signed the \(library.name) support library: \(count) files.")
            reports.append(Report(payloadID: "support/\(library.name)", signedFiles: count))
        }
        return reports
    }
}
