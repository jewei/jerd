import Foundation
import JerdFoundation
import JerdProcess
import JerdTunnels
import Testing

@Suite struct TunnelTokenTests {
    @Test func aValidTokenExposesItsTunnelAndSecretForRedaction() throws {
        let token = try TunnelToken(TokenSamples.valid)
        #expect(token.accountTag == "account")
        #expect(token.tunnelID == UUID(uuidString: TokenSamples.tunnelID))
        #expect(token.secret == TokenSamples.secret)
        #expect(token.redactedValues == [TokenSamples.valid, TokenSamples.secret])
    }

    @Test(arguments: [
        "", "cloudflared tunnel run --token secret", "token with spaces", "tab\ttoken", "caf\u{E9}",
        String(repeating: "A", count: TunnelToken.maximumBytes + 1),
    ])
    func textWithSpacesOrBadCharactersIsRefused(_ text: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.tokenCharacters)) { try TunnelToken(text) }
    }

    @Test(arguments: [
        "not-a-token",
        Data("not json".utf8).base64EncodedString(),
        TokenSamples.token(account: "", tunnel: TokenSamples.tunnelID, secret: "s"),
        TokenSamples.token(account: "a", tunnel: TokenSamples.tunnelID, secret: ""),
        TokenSamples.token(account: "a", tunnel: "not-a-uuid", secret: "s"),
        Data(#"{"a":"a","s":"s"}"#.utf8).base64EncodedString(),
    ])
    func aMalformedPayloadIsRefused(_ text: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.tokenFormat)) { try TunnelToken(text) }
    }

    @Test func aRotatedTokenIdentifiesTheSameRemoteTunnel() throws {
        #expect(TunnelToken.tunnelID(of: TokenSamples.rotated) == TunnelToken.tunnelID(of: TokenSamples.valid))
        #expect(TunnelToken.tunnelID(of: TokenSamples.other) != TunnelToken.tunnelID(of: TokenSamples.valid))
        #expect(TunnelToken.tunnelID(of: "not-a-token") == nil)
    }

    @Test func descriptionsAndDumpsNeverShowTheToken() throws {
        let token = try TunnelToken(TokenSamples.valid)
        var dumped = ""
        dump(token, to: &dumped)
        for text in [String(describing: token), String(reflecting: token), "\(token)", dumped] {
            #expect(!text.contains(TokenSamples.valid))
            #expect(!text.contains(TokenSamples.secret))
        }
        #expect(String(describing: token) == LogRedactor.marker)
    }
}
