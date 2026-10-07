import Foundation
import JerdFoundation

/// A Sparkle-signed feed split into its signed content and its signature block.
///
/// Sparkle 2 (`SPUExtractAppcastContent`) signs the bytes before the last
/// `<!-- sparkle-signatures:\n` and appends `edSignature: <base64>` and `length: <count>` lines
/// and `-->`. `sign_update` always writes the exact content length; a different length means the
/// feed changed after signing.
public struct SignedFeed: Equatable, Sendable {
    static let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    static let suffix = Data("-->".utf8)

    /// The signed bytes.
    public let content: Data
    /// The 64-byte Ed25519 signature.
    public let signature: Data

    /// Splits feed bytes.
    /// - Throws: `.invalid` when the block is missing or malformed, or when its length is not the content length.
    public init(_ data: Data) throws {
        guard let start = data.range(of: Self.prefix, options: .backwards),
            let end = data.range(of: Self.suffix, in: start.upperBound..<data.endIndex)
        else { throw JerdError.invalid("The app update feed has no signature.") }
        let block = String(decoding: data[start.upperBound..<end.lowerBound], as: UTF8.self)
        let fields = Self.fields(block)
        content = data[data.startIndex..<start.lowerBound]
        guard let encoded = fields["edSignature"], let signature = Data(base64Encoded: encoded), signature.count == 64
        else { throw JerdError.invalid("The app update feed signature is malformed.") }
        guard fields["length"] == String(content.count) else {
            throw JerdError.invalid("The app update feed changed after it was signed.")
        }
        self.signature = signature
    }

    /// The `name: value` lines of the block. As in Sparkle, a later line with the same name wins.
    static func fields(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in block.split(whereSeparator: \.isNewline) {
            for name in ["edSignature", "length"] where line.hasPrefix("\(name):") {
                fields[name] = line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
            }
        }
        return fields
    }
}
