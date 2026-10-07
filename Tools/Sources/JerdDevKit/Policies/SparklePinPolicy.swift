import Foundation

/// The Sparkle version in `project.yml` must be an exact version and must equal the version that the
/// committed `Package.resolved` pins. Otherwise a build resolves a different Sparkle than the review saw.
enum SparklePinPolicy {
    static let specFile = "project.yml"
    static let resolvedFile = "Jerd.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

    private struct Resolved: Decodable {
        struct Pin: Decodable {
            struct State: Decodable {
                var version: String?
            }

            var identity: String
            var state: State
        }

        var pins: [Pin]
    }

    static func findings(projectSpec: String, packageResolved: Data) -> [PolicyFinding] {
        guard let specVersion = exactVersion(ofPackage: "Sparkle", inProjectSpec: projectSpec) else {
            return [PolicyFinding(file: specFile, message: "The Sparkle package must use exactVersion.")]
        }
        guard let resolved = try? JSONDecoder().decode(Resolved.self, from: packageResolved) else {
            return [PolicyFinding(file: resolvedFile, message: "The file is not a valid Package.resolved file.")]
        }
        guard let pinned = resolved.pins.first(where: { $0.identity == "sparkle" })?.state.version else {
            return [PolicyFinding(file: resolvedFile, message: "The file has no Sparkle version.")]
        }
        guard pinned == specVersion else {
            return [
                PolicyFinding(
                    file: resolvedFile,
                    message: "Sparkle is pinned to \(pinned), but \(specFile) requires \(specVersion). "
                        + "Resolve packages again in Xcode and commit Package.resolved.")
            ]
        }
        return []
    }

    /// Reads `exactVersion` from the package's block under the top-level `packages:` key.
    /// It reads only this simple form; any other form means "not an exact version".
    static func exactVersion(ofPackage name: String, inProjectSpec spec: String) -> String? {
        var section: Substring?
        var packageIndent: Int?
        for line in spec.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix { $0 == " " }.count
            let content = line.dropFirst(indent)
            if content.isEmpty || content.hasPrefix("#") { continue }
            if indent == 0 {
                section = content
                packageIndent = nil
                continue
            }
            guard section == "packages:" else { continue }
            if let current = packageIndent, indent > current {
                if content.hasPrefix("exactVersion:") {
                    let value = content.dropFirst("exactVersion:".count).trimmingCharacters(in: .whitespaces)
                    return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            } else {
                packageIndent = content == "\(name):" ? indent : nil
            }
        }
        return nil
    }
}
