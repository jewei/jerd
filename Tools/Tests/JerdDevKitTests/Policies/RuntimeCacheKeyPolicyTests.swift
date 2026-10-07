import Foundation
import Testing

@testable import JerdDevKit

@Suite("Runtime cache key policy")
struct RuntimeCacheKeyPolicyTests {
    static let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func workflow(patterns: [String]) -> String {
        let arguments = patterns.map { "'\($0)'" }.joined(separator: ", ")
        return """
            steps:
              - name: Restore prepared runtimes
                uses: actions/cache/restore@v6
                with:
                  key: runtimes-${{ runner.os }}-${{ hashFiles(\(arguments)) }}
            """
    }

    private func findings(_ text: String, pathExists: (String) -> Bool = { _ in true }) -> [String] {
        RuntimeCacheKeyPolicy.findings(workflow: text, pathExists: pathExists).map(\.message)
    }

    @Test("accepts a key that hashes every preparation input")
    func acceptsCompleteKey() {
        #expect(findings(workflow(patterns: RuntimeCacheKeyPolicy.requiredInputs)).isEmpty)
    }

    @Test("refuses the key that hashes only the catalog and the Laravel lock file")
    func refusesCatalogOnlyKey() {
        let messages = findings(
            workflow(patterns: ["Runtimes/runtimes.json", "Runtimes/laravel-installer/composer.lock"]))
        #expect(messages.contains("The runtime cache key does not hash Configuration/Base.xcconfig."))
        #expect(
            messages.contains(
                "The runtime cache key does not hash Packages/JerdKit/Sources/JerdRuntimes/Preparation/**."))
        #expect(messages.contains("The runtime cache key does not hash Tools/Sources/JerdDevKit/Runtimes/**."))
    }

    @Test("refuses a pattern whose folder does not exist")
    func refusesMissingFolder() {
        let patterns = RuntimeCacheKeyPolicy.requiredInputs + ["Packages/Old/**"]
        let messages = findings(workflow(patterns: patterns)) { $0 != "Packages/Old" }
        #expect(messages == ["The runtime cache key pattern Packages/Old/** names no file."])
    }

    @Test("refuses a workflow without the runtime cache key")
    func refusesMissingKey() {
        #expect(findings("steps: []\n") == ["The runtime cache key with hashFiles(…) is missing."])
    }

    @Test("reads the fixed part of a pattern before the first glob character")
    func readsFixedPart() {
        #expect(RuntimeCacheKeyPolicy.fixedPart(of: "Runtimes/**") == "Runtimes")
        #expect(RuntimeCacheKeyPolicy.fixedPart(of: "Configuration/Base.xcconfig") == "Configuration/Base.xcconfig")
    }

    @Test("accepts the committed CI workflow")
    func acceptsCommittedWorkflow() throws {
        let root = Self.repositoryRoot
        let text = try String(contentsOf: root.appending(path: RuntimeCacheKeyPolicy.file), encoding: .utf8)
        let messages = findings(text) { FileManager.default.fileExists(atPath: root.appending(path: $0).path) }
        #expect(messages.isEmpty)
    }
}
