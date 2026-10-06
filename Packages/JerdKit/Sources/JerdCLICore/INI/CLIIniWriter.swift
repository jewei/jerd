import Foundation
import JerdFoundation
import JerdWeb

/// Writes the CLI INI files and the empty scan folder in `runtimes/configuration/`.
///
/// There are two INI files: `cli.ini` without the local CA and `cli-local-tls.ini` with it. A
/// command with its own trust variables then never rewrites the file that a concurrent default
/// command reads. A file is written only when it is absent or its bytes differ.
struct CLIIniWriter: Sendable {
    /// The read limit of an existing INI file.
    static let sizeLimit = 65_536

    private let layout: DataLayout

    init(layout: DataLayout) {
        self.layout = layout
    }

    /// Writes the INI for `caBundle` (nil: no local CA) when needed and returns its URL.
    /// - Throws: `.invalid` for a CA path that INI text cannot hold; file errors.
    func writeINI(caBundle: URL?) throws -> URL {
        let runtimes = layout.runtimes
        let file = caBundle == nil ? runtimes.cliINIFile : runtimes.cliLocalTLSINIFile
        let data = Data(try PHPIniPolicy.cliFile(caBundle: caBundle).utf8)
        try OwnedDirectory.create(runtimes.cliConfigurationDirectory, within: layout.root)
        let isCurrent =
            try FileProbe.presence(at: file) != .absent && AtomicFile.read(file, limit: Self.sizeLimit) == data
        if !isCurrent { try AtomicFile.write(data, to: file, durability: .standard) }
        return file
    }

    /// Creates the empty folder for `PHP_INI_SCAN_DIR` and returns it.
    func prepareEmptyScanDirectory() throws -> URL {
        let folder = layout.runtimes.cliEmptyINIDirectory
        try OwnedDirectory.create(folder, within: layout.root)
        return folder
    }
}
