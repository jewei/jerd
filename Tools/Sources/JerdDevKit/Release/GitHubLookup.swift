import Foundation

/// Parses `gh` output. Each list query uses `--jq` to print one compact JSON object per line, so a
/// `--paginate` result never depends on how pages are joined.
enum GitHubLookup {
    /// One line of the tag query: `{ref, sha, type}`.
    struct Reference: Codable, Equatable, Sendable {
        var ref: String
        var sha: String
        var type: String
    }

    /// One line of the release query: `{tag, draft, target}`.
    struct Release: Codable, Equatable, Sendable {
        var tag: String
        var draft: Bool
        var target: String
    }

    /// One pull request: `{number, state}` with state `OPEN`, `CLOSED`, or `MERGED`.
    struct PullRequest: Codable, Equatable, Sendable {
        var number: Int
        var state: String
    }

    static let referenceFilter = ".[] | {ref: .ref, sha: .object.sha, type: .object.type}"
    static let releaseFilter = ".[] | {tag: .tag_name, draft: .draft, target: .target_commitish}"

    /// The reference whose name is exactly `refs/tags/<tag>`. `matching-refs` is a prefix search, so
    /// `v0.1.0` also returns `v0.1.0-rc1`; only the exact name counts.
    static func exactTag(_ tag: String, in output: String) throws -> Reference? {
        try lines(output, as: Reference.self).first { $0.ref == "refs/tags/\(tag)" }
    }

    /// The release, draft or public, whose tag name is exactly `tag`. A draft has no Git tag yet, so
    /// only the release list finds it.
    static func release(_ tag: String, in output: String) throws -> Release? {
        try lines(output, as: Release.self).first { $0.tag == tag }
    }

    static func pullRequest(_ output: String) throws -> PullRequest {
        try decode(PullRequest.self, Data(output.utf8))
    }

    static func pullRequests(_ output: String) throws -> [PullRequest] {
        try decode([PullRequest].self, Data(output.utf8))
    }

    /// `gh pr create` prints the URL of the new pull request, for example `…/pull/12`.
    static func pullRequestNumber(fromCreateOutput output: String) throws -> Int {
        let url = output.split(whereSeparator: \.isWhitespace).last { $0.contains("/pull/") }
        guard let url, let number = url.split(separator: "/").last.flatMap({ Int($0) }) else {
            throw DevFailure.checkFailed("gh did not print the URL of the feed pull request.")
        }
        return number
    }

    private static func lines<Value: Decodable>(_ output: String, as type: Value.Type) throws -> [Value] {
        try output.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            try decode(type, Data($0.utf8))
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DevFailure.checkFailed("GitHub returned an answer that cannot be read.")
        }
    }
}
