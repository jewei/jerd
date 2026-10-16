/// Looks up the public hostname of a tunnel. It never sends a request to that hostname.
public protocol PublicHostnameResolving: Sendable {
    func status(of hostname: String) async -> PublicHostnameStatus
}
