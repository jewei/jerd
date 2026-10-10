import Foundation
import JerdFoundation
import JerdProcess

/// A checked token of an existing Cloudflare tunnel.
///
/// The token is standard base64 of the JSON `{"a": <account tag>, "t": <tunnel UUID>, "s": <secret>}`.
/// Its text never appears in a description, a dump, or a mirror, so a log statement cannot leak it.
public struct TunnelToken: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// The longest token that Jerd accepts, in bytes.
    public static let maximumBytes = 16_384

    /// The full token text. It goes only to the Keychain and to the connector's environment.
    package let value: String
    package let accountTag: String
    /// The remote tunnel. Two registrations for one remote tunnel are refused.
    package let tunnelID: UUID
    package let secret: String

    /// Checks the characters, then the payload.
    /// - Throws: `.invalid` with a message that tells the user what to paste.
    public init(_ text: String) throws {
        guard !text.isEmpty, text.utf8.count <= Self.maximumBytes, text.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw JerdError.invalid(TunnelMessage.tokenCharacters) }
        guard let payload = Payload.decode(text), !payload.accountTag.isEmpty, !payload.secret.isEmpty else {
            throw JerdError.invalid(TunnelMessage.tokenFormat)
        }
        value = text
        accountTag = payload.accountTag
        tunnelID = payload.tunnelID
        secret = payload.secret
    }

    /// The remote tunnel ID of a saved token text, or nil when the text is not a valid token.
    package static func tunnelID(of text: String) -> UUID? {
        (try? TunnelToken(text))?.tunnelID
    }

    /// The values that logs and messages must never show: the whole token and its secret.
    package var redactedValues: [String] { [value, secret] }

    public var description: String { LogRedactor.marker }
    public var debugDescription: String { "TunnelToken(\(LogRedactor.marker))" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }

    private struct Payload: Decodable {
        let accountTag: String
        let tunnelID: UUID
        let secret: String

        enum CodingKeys: String, CodingKey {
            case accountTag = "a"
            case tunnelID = "t"
            case secret = "s"
        }

        static func decode(_ text: String) -> Payload? {
            guard let data = Data(base64Encoded: text) else { return nil }
            return try? JSONDecoder().decode(Payload.self, from: data)
        }
    }
}
