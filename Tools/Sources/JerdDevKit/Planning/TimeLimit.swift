/// The time limit of each kind of command. Each limit is far above a normal run on a CI Mac, so a
/// limit stops only a command that hangs.
enum TimeLimit {
    static let probe: Duration = .seconds(60)
    /// The first run of a binary in a new folder. macOS scans an unknown binary before it runs, and
    /// for a large binary such as RustFS this took more than 60 s on a busy Mac.
    static let firstRun: Duration = .seconds(180)
    static let git: Duration = .seconds(120)
    static let generate: Duration = .seconds(300)
    static let format: Duration = .seconds(600)
    static let test: Duration = .seconds(30 * 60)
    static let build: Duration = .seconds(40 * 60)
    static let snapshots: Duration = .seconds(20 * 60)

    /// Copies one prepared payload folder (about 1 GB at most) into the app bundle.
    static let payloadCopy: Duration = .seconds(10 * 60)
    /// Configures, compiles, and installs a support library such as XZ.
    static let supportBuild: Duration = .seconds(15 * 60)
    /// Signs or verifies the signature of one file or bundle. A timestamp needs the network.
    static let codeSigning: Duration = .seconds(5 * 60)
    /// Copies or compresses the whole app (about 1.2 GB) with `ditto`.
    static let appCopy: Duration = .seconds(15 * 60)
    /// Creates, verifies, attaches, or detaches the disk image.
    static let diskImage: Duration = .seconds(20 * 60)
    /// Archives the Release app with `xcodebuild archive`.
    static let archive: Duration = .seconds(60 * 60)
    /// One notarization: upload, Apple's processing (`--timeout 45m`), and the result.
    static let notarization: Duration = .seconds(60 * 60)
    /// A Gatekeeper assessment, which can ask Apple online.
    static let assessment: Duration = .seconds(5 * 60)
    /// One GitHub command; the upload of the release assets uses `transfer`.
    static let gitHub: Duration = .seconds(5 * 60)
    static let transfer: Duration = .seconds(60 * 60)
    /// One manual harness case, for example one Sparkle installation.
    static let harnessCase: Duration = .seconds(3 * 60)
}
