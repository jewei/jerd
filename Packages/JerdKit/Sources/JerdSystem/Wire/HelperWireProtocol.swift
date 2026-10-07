import Foundation
import JerdFoundation

/// The fixed facts of the helper XPC wire: selectors, payload limits, and the JSON coding of DTOs.
///
/// Every DTO is JSON from a `JSONEncoder` with default options: `Data` is base64 text, `UUID` is
/// uppercase text, enums are raw strings, and a nil optional is omitted. An older helper keeps
/// running during an app update, so a new DTO field must always be optional.
public enum HelperWireProtocol {
    /// The selectors of `JerdHelperProtocol`, sorted.
    public static let helperSelectors = [
        "acquireListenersWithReply:", "configureSite:reply:", "recoverSetup:reply:",
        "releaseListenersWithReply:", "removeSetupWithReply:", "statusWithReply:",
    ]
    /// The selectors of `JerdTrustConsentProtocol`.
    public static let consentSelectors = ["changeTrust:reply:"]

    /// A configure payload must be smaller than this (bytes).
    public static let configureLimit = 131_072
    /// A recovery approval payload must be smaller than this (bytes).
    public static let recoverLimit = 4_096
    /// A consent request payload must be smaller than this (bytes).
    public static let consentLimit = 131_072

    /// Encodes a DTO with the default encoder options of the wire.
    public static func encode(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Decodes a DTO that is smaller than `limit` bytes.
    /// - Throws: `.invalid` when the payload is too large or does not decode.
    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data, limit: Int) throws -> Value {
        guard data.count < limit else {
            throw JerdError.invalid("The request to the Jerd helper is too large. No change was made.")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw JerdError.invalid("The request to the Jerd helper is not valid. No change was made.")
        }
    }
}
