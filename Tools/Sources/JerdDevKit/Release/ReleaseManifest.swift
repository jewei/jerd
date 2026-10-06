import Foundation
import JerdFoundation
import JerdManifest

/// `release.json`: what a prepared candidate contains and where it came from. Validation and
/// publication trust only the files that it lists with their SHA-256.
struct ReleaseManifest: Codable, Equatable, Sendable {
    struct Notarization: Codable, Equatable, Sendable {
        var app: String
        var dmg: String
    }

    static let fileName = "release.json"
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var version: String
    var build: String
    var teamID: String
    var minimumMacOS: String
    var repository = ReleaseNames.repository
    var sourceCommit: String
    var sourceFeedSHA256: String
    var dmg: String
    var symbols: String
    /// The published files (disk image, symbols, feed, notes) and their SHA-256.
    var files: [String: String]
    var notarization: Notarization
    var testedSystem: String
    var architecture = ReleaseNames.architecture

    var releaseVersion: ReleaseVersion {
        get throws {
            guard let value = ReleaseVersion.release(version) else { throw invalid("an invalid version") }
            return value
        }
    }

    var buildNumber: Int {
        get throws {
            guard let value = ReleaseVersion.build(build) else { throw invalid("an invalid build") }
            return value
        }
    }

    var minimum: ReleaseVersion {
        get throws {
            guard let value = ReleaseVersion(minimumMacOS, parts: 1...3) else {
                throw invalid("an invalid minimum macOS version")
            }
            return value
        }
    }

    /// The structural rules of spec G 2.6 step 1 to 3, without reading files.
    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw invalid("an unknown format version") }
        guard repository == ReleaseNames.repository, architecture == ReleaseNames.architecture else {
            throw invalid("an unexpected repository or architecture")
        }
        guard PayloadReceipt.isTeamID(teamID) else { throw invalid("an invalid team") }
        guard sourceCommit.count == 40, HexEncoding.isHex(sourceCommit, length: 40) else {
            throw invalid("an invalid source commit")
        }
        let version = try releaseVersion
        let build = try buildNumber
        _ = try minimum
        guard dmg == ReleaseNames.diskImage(version), symbols == ReleaseNames.symbols(version, build: build) else {
            throw invalid("unexpected artifact names")
        }
        guard Set(files.keys) == [dmg, symbols, CandidateLayout.feedName, CandidateLayout.notesName],
            files.values.allSatisfy(FileDigest.isSHA256Hex)
        else { throw invalid("missing or unexpected artifacts") }
    }

    /// Sorted, indented JSON with a final line break, so that the record is easy to review.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    static func decode(_ data: Data) throws -> ReleaseManifest {
        let manifest: ReleaseManifest
        do {
            manifest = try JSONDecoder().decode(ReleaseManifest.self, from: data)
        } catch {
            throw DevFailure.checkFailed("release.json cannot be read: \(error.localizedDescription)")
        }
        try manifest.validate()
        return manifest
    }

    private func invalid(_ problem: String) -> DevFailure {
        DevFailure.checkFailed("release.json has \(problem).")
    }
}
