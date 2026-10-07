import Foundation

/// Parses `gh api` output. Each list query uses `--jq` to print one compact JSON object per line, so a
/// `--paginate` result never depends on how pages are joined.
enum GitHubLookup {
    /// One line of the release query: `{tag, draft}`.
    struct Release: Codable, Equatable, Sendable {
        var tag: String
        var draft: Bool
    }

    /// One line of the check-run query: `{name, status, conclusion}`.
    struct CheckRun: Codable, Equatable, Sendable {
        var name: String
        var status: String
        var conclusion: String?
    }

    /// One line of the asset query: `{name, size, digest}`. GitHub gives the digest as `sha256:<hex>`.
    struct Asset: Codable, Equatable, Sendable {
        var name: String
        var size: Int64
        var digest: String?
    }

    static let releaseFilter = ".[] | {tag: .tag_name, draft: .draft}"
    static let assetFilter = ".assets[] | {name: .name, size: .size, digest: .digest}"

    /// Nil when every expected asset exists with its size and digest; otherwise what differs.
    static func assetProblem(expected: [String: Asset], in output: String) throws -> String? {
        let assets = try lines(output, as: Asset.self)
        for (name, wanted) in expected.sorted(by: { $0.key < $1.key }) {
            guard let asset = assets.first(where: { $0.name == name }) else { return "has no asset \(name)" }
            guard asset.size == wanted.size, asset.digest?.lowercased() == wanted.digest?.lowercased() else {
                return "has an asset \(name) that differs from the candidate (size \(asset.size), "
                    + "digest \(asset.digest ?? "none"))"
            }
        }
        return nil
    }
    static let checkRunFilter = ".check_runs[] | {name: .name, status: .status, conclusion: .conclusion}"

    /// The release, draft or public, whose tag name is exactly `tag`. A draft has no Git tag, so only
    /// the release list finds it.
    static func release(_ tag: String, in output: String) throws -> Release? {
        try lines(output, as: Release.self).first { $0.tag == tag }
    }

    /// Nil when a check run named `name` succeeded; otherwise why the commit is not ready. A re-run of
    /// a failed job adds a successful run, so one success is enough.
    static func checkProblem(named name: String, in output: String) throws -> String? {
        let runs = try lines(output, as: CheckRun.self).filter { $0.name == name }
        if runs.contains(where: { $0.status == "completed" && $0.conclusion == "success" }) { return nil }
        if runs.isEmpty { return "has no \(name) result" }
        if runs.contains(where: { $0.status != "completed" }) { return "has a \(name) run that is not finished" }
        let conclusions = Set(runs.compactMap(\.conclusion)).sorted().joined(separator: ", ")
        return "has no successful \(name) run (\(conclusions))"
    }

    private static func lines<Value: Decodable>(_ output: String, as type: Value.Type) throws -> [Value] {
        try output.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            do {
                return try JSONDecoder().decode(type, from: Data($0.utf8))
            } catch {
                throw DevFailure.checkFailed("GitHub returned an answer that cannot be read.")
            }
        }
    }
}
