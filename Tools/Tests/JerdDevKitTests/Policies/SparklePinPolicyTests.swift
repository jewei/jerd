import Foundation
import Testing

@testable import JerdDevKit

@Suite("Sparkle pin policy")
struct SparklePinPolicyTests {
    static let projectSpec = """
        name: Jerd
        packages:
          JerdKit:
            path: Packages/JerdKit
          Sparkle:
            url: https://github.com/sparkle-project/Sparkle
            exactVersion: 2.10.0
        targets:
          Jerd:
            type: application
        """

    /// The committed `Package.resolved` of the Xcode project.
    static let packageResolved = """
        {
          "originHash" : "1a351a2b08cd9cbeb2df973c98aecdcc1e3a85f673fd93afa2b3b13020f030a7",
          "pins" : [
            {
              "identity" : "sparkle",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/sparkle-project/Sparkle",
              "state" : {
                "revision" : "eef1a539a373c1f1a320624b1130fc5de7b2e100",
                "version" : "2.10.0"
              }
            }
          ],
          "version" : 3
        }
        """

    private func findings(spec: String = projectSpec, resolved: String = packageResolved) -> [String] {
        SparklePinPolicy.findings(projectSpec: spec, packageResolved: Data(resolved.utf8)).map(\.message)
    }

    @Test("accepts equal versions")
    func acceptsEqualVersions() {
        #expect(findings().isEmpty)
    }

    @Test("reads exactVersion only from the Sparkle package block")
    func readsExactVersion() {
        #expect(SparklePinPolicy.exactVersion(ofPackage: "Sparkle", inProjectSpec: Self.projectSpec) == "2.10.0")
        #expect(SparklePinPolicy.exactVersion(ofPackage: "JerdKit", inProjectSpec: Self.projectSpec) == nil)
        let quoted = Self.projectSpec.replacingOccurrences(of: "exactVersion: 2.10.0", with: "exactVersion: \"2.10.0\"")
        #expect(SparklePinPolicy.exactVersion(ofPackage: "Sparkle", inProjectSpec: quoted) == "2.10.0")
    }

    @Test("reports a version range instead of an exact version")
    func reportsRange() {
        let spec = Self.projectSpec.replacingOccurrences(of: "exactVersion: 2.10.0", with: "from: 2.10.0")
        #expect(findings(spec: spec) == ["The Sparkle package must use exactVersion."])
    }

    @Test("reports a resolved version that differs from the spec")
    func reportsDrift() {
        let resolved = Self.packageResolved.replacingOccurrences(of: "\"2.10.0\"", with: "\"2.11.0\"")
        #expect(
            findings(resolved: resolved) == [
                "Sparkle is pinned to 2.11.0, but project.yml requires 2.10.0. "
                    + "Resolve packages again in Xcode and commit Package.resolved."
            ])
    }

    @Test("reports a resolved file without Sparkle or with invalid JSON")
    func reportsBadResolvedFile() {
        let withoutSparkle = Self.packageResolved.replacingOccurrences(of: "\"sparkle\"", with: "\"other\"")
        #expect(findings(resolved: withoutSparkle) == ["The file has no Sparkle version."])
        #expect(findings(resolved: "{") == ["The file is not a valid Package.resolved file."])
    }
}
