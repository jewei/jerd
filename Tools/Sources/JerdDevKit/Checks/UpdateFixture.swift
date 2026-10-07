import Foundation

/// What every update case shares: the compiled test app, the temporary test key, the signing
/// identity, and Jerd's Info.plist, whose Sparkle keys every test app copies.
struct UpdateFixture: Sendable {
    var binary: URL
    /// The private test key file (mode 0600). It exists only in the work folder of one run.
    var key: URL
    var publicKey: String
    var identity: String
    var jerdInfoPlist: Data
}
