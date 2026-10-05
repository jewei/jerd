import Foundation

/// Reads the `schemaVersion` key of a versioned document before the full decode, for migrations.
public enum SchemaVersion {
    /// Decodes only `{"schemaVersion": <integer>}`. The key is required.
    public static func read(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> Int {
        try decoder.decode(Header.self, from: data).schemaVersion
    }

    /// The error for a version that this build cannot read. The file is preserved.
    public static func unsupported(_ version: Int) -> JerdError {
        .corrupt("Unsupported format version: \(version).")
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }
}
