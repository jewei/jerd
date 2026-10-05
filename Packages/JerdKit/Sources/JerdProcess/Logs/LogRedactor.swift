import Foundation
import JerdFoundation

/// Replaces secrets in a byte stream before the bytes reach a log. Pure and incremental.
///
/// Matching is on raw bytes, leftmost and longest first. Bytes that could be the start of a
/// secret are held until the next chunk decides, so a secret split between two writes stays
/// private. The held bytes are always fewer than the longest secret, so memory is bounded.
public struct LogRedactor: Sendable {
    /// The text that replaces each secret. Jerd uses this one marker everywhere.
    public static let marker = "[redacted]"
    /// The most secrets one redactor accepts.
    public static let maximumValues = 32
    /// The longest secret one redactor accepts, in UTF-8 bytes.
    public static let maximumValueBytes = 65_536

    private let secrets: [[UInt8]]
    private var pending: [UInt8] = []

    /// Empty values are ignored and duplicates are removed.
    /// - Throws: `.invalid` when there are more than 32 values or one is longer than 65 536 bytes.
    public init(values: [String]) throws {
        guard values.count <= Self.maximumValues, values.allSatisfy({ $0.utf8.count <= Self.maximumValueBytes }) else {
            throw JerdError.invalid("The log redaction configuration is too large.")
        }
        self.init(unlimited: values)
    }

    private init(unlimited values: [String]) {
        secrets = Set(values.filter { !$0.isEmpty }).map { Array($0.utf8) }.sorted { $0.count > $1.count }
    }

    /// Redacts one chunk. With `final: true`, held bytes are released as plain text.
    public mutating func append(_ bytes: Data, final: Bool = false) -> Data {
        pending.append(contentsOf: bytes)
        var output = Data()
        var index = 0
        while index < pending.count {
            let remaining = pending.count - index
            // Hold a possible secret start before any full match, so a short secret that is a
            // prefix of a longer one cannot release the longer secret's first bytes.
            if !final,
                secrets.contains(where: {
                    remaining < $0.count && pending[index...].elementsEqual($0.prefix(remaining))
                })
            {
                break
            }
            if let secret = secrets.first(where: {
                remaining >= $0.count && pending[index..<(index + $0.count)].elementsEqual($0)
            }) {
                output.append(contentsOf: Self.marker.utf8)
                index += secret.count
            } else {
                output.append(pending[index])
                index += 1
            }
        }
        pending.removeFirst(index)
        return output
    }

    /// Replaces every secret in a complete text, for messages and log tails shown to a user.
    public static func redact(_ text: String, values: [String]) -> String {
        var redactor = LogRedactor(unlimited: values)
        return String(decoding: redactor.append(Data(text.utf8), final: true), as: UTF8.self)
    }
}
