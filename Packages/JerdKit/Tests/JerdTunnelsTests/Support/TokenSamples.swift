import Foundation

/// Sample tokens in the format of Cloudflare's remotely managed tunnels.
enum TokenSamples {
    static let tunnelID = "32394787-9B89-41AE-A065-57520475754A"
    static let secret = "private-token-secret"

    /// base64 of `{"a":"account","t":"<tunnelID>","s":"private-token-secret"}`.
    static let valid = token(account: "account", tunnel: tunnelID, secret: secret)
    /// The same remote tunnel with a rotated secret.
    static let rotated = token(account: "account", tunnel: tunnelID, secret: "rotated-secret")
    /// Another remote tunnel.
    static let other = token(account: "account", tunnel: "C52B93C8-AD2F-4F26-9252-9195BB7E236A", secret: "other-secret")

    static func token(account: String, tunnel: String, secret: String) -> String {
        Data(#"{"a":"\#(account)","t":"\#(tunnel)","s":"\#(secret)"}"#.utf8).base64EncodedString()
    }
}
