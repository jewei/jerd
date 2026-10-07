import Foundation

/// The files of one private release candidate in `.build/releases/Jerd-<version>-<build>-<random>/`.
struct CandidateLayout: Equatable, Sendable {
    static let feedName = "appcast.xml"
    static let notesName = "release-notes.md"
    static let namePrefix = "Jerd-"

    let root: URL

    var state: URL { file(ReleaseState.fileName) }
    var manifest: URL { file(ReleaseManifest.fileName) }
    var sourceFeed: URL { file("source-appcast.xml") }
    var feed: URL { file(Self.feedName) }
    var notes: URL { file(Self.notesName) }
    var archive: URL { file("Jerd.xcarchive") }
    var derivedData: URL { file("DerivedData") }
    var app: URL { file("export/Jerd.app") }
    var symbols: URL { file("symbols") }
    var diskImageFolder: URL { file("disk-image") }
    var appSubmission: URL { file("notary-app.zip") }
    var entitlements: URL { file("entitlements") }
    var integration: URL { file("integration") }
    var publishedAssets: URL { file("published-assets") }
    /// The temporary Git index of the feed commit. Publication commits without a worktree.
    var feedIndex: URL { file("feed-index") }

    func file(_ name: String) -> URL { root.appending(path: name) }

    func log(_ name: String) -> URL { file("\(name).log") }

    /// The payloads inside the exported app.
    var appPayloads: URL { app.appending(path: "Contents/Resources/RuntimePayloads") }
}
