import Foundation

/// The files of one release candidate in `.build/releases/Jerd-<version>-<build>/` (mode 0700).
/// A new run of the same version and build replaces the folder. A run stops before that when the tag
/// of the version exists, so the files that the recovery commands name stay.
struct CandidateLayout: Equatable, Sendable {
    static let feedName = "appcast.xml"
    static let notesName = "release-notes.md"

    let root: URL

    init(root: URL) { self.root = root }

    init(releases: URL, version: ReleaseVersion, build: Int) {
        root = releases.appending(path: "Jerd-\(version)-\(build)", directoryHint: .isDirectory)
    }

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

    func file(_ name: String) -> URL { root.appending(path: name) }

    func log(_ name: String) -> URL { file("\(name).log") }

    /// The payloads inside the exported app.
    var appPayloads: URL { app.appending(path: "Contents/Resources/RuntimePayloads") }
}
