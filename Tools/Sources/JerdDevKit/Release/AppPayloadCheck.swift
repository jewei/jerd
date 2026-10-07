import Foundation
import JerdManifest

/// Checks the signed runtime payloads inside an app: every file matches its receipt, every receipt
/// carries the release team, and every Mach-O file runs on the minimum macOS and needs only system
/// libraries and files of its own payload.
struct AppPayloadCheck: Sendable {
    let shell: ReleaseShell
    let team: String
    let minimumMacOS: ReleaseVersion

    /// - Returns: the payload Mach-O files, which must be signed with their file name as identifier.
    func verify(_ root: URL) async throws -> [AppVerifier.SignedCode] {
        var code: [AppVerifier.SignedCode] = []
        for payload in try PayloadSigner.verifiedPayloads(in: root) {
            guard payload.receipt.signing?.teamID == team else {
                throw DevFailure.checkFailed("The \(payload.pin.id) receipt has no signing record of team \(team).")
            }
            let resolver = DependencyResolver(payload: payload.origin)
            for path in payload.receipt.fileRecords.keys.sorted() {
                let file = path.url(in: payload.origin)
                guard MachOFile.isMachO(file) else { continue }
                try await checkLoadCommands(file, resolver: resolver)
                code.append(.init(file: file, identifier: .exact(file.lastPathComponent)))
            }
        }
        return code + (try await verifySupport(root))
    }

    /// Each embedded support library matches its signed receipt, carries the release team, runs on
    /// the minimum macOS, and needs only system libraries.
    func verifySupport(_ root: URL) async throws -> [AppVerifier.SignedCode] {
        let catalog = try PayloadInventory.catalog(at: root.appending(path: RuntimePinCatalog.fileName))
        var code: [AppVerifier.SignedCode] = []
        for library in try EmbeddedSupport.verified(in: root, catalog: catalog) {
            guard library.receipt.signing?.teamID == team else {
                throw DevFailure.checkFailed(
                    "The \(library.name) support receipt has no signing record of team \(team).")
            }
            let resolver = DependencyResolver(payload: library.folder)
            for name in library.receipt.files.keys.sorted() {
                let file = library.folder.appending(path: name)
                guard MachOFile.isMachO(file) else { continue }
                try await checkLoadCommands(file, resolver: resolver)
                code.append(.init(file: file, identifier: .exact(name)))
            }
        }
        return code
    }

    func checkLoadCommands(_ file: URL, resolver: DependencyResolver) async throws {
        let output = try await shell.output(
            SystemProgram.otool, ["-arch", "arm64", "-l", file.path], limit: TimeLimit.probe)
        let info = MachOLoadInfo.parse(output)
        guard let required = ReleaseVersion(info.minimumSystem), required <= minimumMacOS else {
            throw DevFailure.checkFailed(
                "\(file.lastPathComponent) needs macOS \(info.minimumSystem), above the release minimum \(minimumMacOS)."
            )
        }
        for dependency in info.dependencies {
            _ = try resolver.resolve(dependency, of: file, rpaths: info.rpaths)
        }
    }
}
