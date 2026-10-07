import Foundation
import JerdFoundation

/// The one formula for the folder name of an installed bundled payload.
///
/// `<payload ID>-<fingerprint>`, where the fingerprint is the first 16 hexadecimal characters of
/// the SHA-256 of the canonical file list. The canonical list has one line per file, sorted by
/// path: `<path>\t<sha256>\t<x or ->\n`. A path cannot contain a tab or a newline (they are
/// control characters, which `RelativePath` refuses), so the text is unambiguous.
///
/// The folder name thus changes whenever a file or its mode changes, for example after the release
/// tool signs the binaries. Different payloads install side by side and never replace each other.
public enum PayloadFolderID {
    /// The number of hexadecimal characters of the fingerprint.
    public static let fingerprintLength = 16

    /// The folder name of a payload with these files.
    public static func make(payloadID: String, files: [RelativePath: PayloadFileRecord]) -> String {
        "\(payloadID)-\(fingerprint(files))"
    }

    /// The fingerprint of a file list.
    public static func fingerprint(_ files: [RelativePath: PayloadFileRecord]) -> String {
        String(FileDigest.hexSHA256(of: canonicalList(files)).prefix(fingerprintLength))
    }

    /// The canonical bytes that the fingerprint hashes.
    public static func canonicalList(_ files: [RelativePath: PayloadFileRecord]) -> Data {
        let lines = files.sorted { Array($0.key.string.utf8).lexicographicallyPrecedes($1.key.string.utf8) }
            .map { path, record in "\(path.string)\t\(record.sha256)\t\(record.executable ? "x" : "-")\n" }
        return Data(lines.joined().utf8)
    }
}
