/// Checks that macOS resolves and trusts a site as a browser would. Tests use a fake.
public protocol TrustProbing: Sendable {
    /// Returns when `https://<hostname>/.jerd/ready` answers through normal resolution and trust.
    func check(hostname: String) async throws
}
