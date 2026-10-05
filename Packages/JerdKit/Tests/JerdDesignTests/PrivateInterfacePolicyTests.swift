import Foundation
import Testing

/// JerdDesign ships in the app. These tests read its sources and prove that it uses no private
/// selector, underscored key, or runtime lookup, and that snapshot code stays in JerdSnapshotSupport.
@Suite("JerdDesign private interface policy")
struct PrivateInterfacePolicyTests {
    /// Patterns that only private or unchecked API use.
    private static let forbiddenPatterns: [(name: String, pattern: String)] = [
        ("an underscored key path", #"\\\._"#),
        ("an underscored member", #"\._[A-Za-z]"#),
        ("an underscored function or property", #"(func|var|let)\s+_[A-Za-z]"#),
        ("an Objective-C exposed member", #"@objc"#),
        ("a selector", #"(NSSelectorFromString|#selector|Selector\()"#),
        ("a key-value lookup", #"(value\(forKey|setValue\(|perform\(\s*(#selector|Selector|NSSelector))"#),
        ("an underscored string", #""_[A-Za-z]"#),
        ("a private import", #"@_spi|@_implementationOnly"#),
    ]

    private static var sourcesFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/JerdDesign")
    }

    private static func sourceFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: sourcesFolder, includingPropertiesForKeys: nil)
        let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        try #require(files.count > 20, "The JerdDesign sources were not found at \(sourcesFolder.path)")
        return files
    }

    @Test("JerdDesign sources use no private selector, underscored key, or runtime lookup")
    func noPrivateInterfaces() throws {
        var findings: [String] = []
        for file in try Self.sourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                for rule in Self.forbiddenPatterns
                where code.range(of: rule.pattern, options: .regularExpression) != nil {
                    findings.append("\(file.lastPathComponent):\(index + 1) uses \(rule.name)")
                }
            }
        }
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    @Test("Snapshot rendering and the gallery are not part of JerdDesign")
    func noSnapshotCode() throws {
        let names = try Self.sourceFiles().map(\.lastPathComponent)
        #expect(
            names.filter { $0.contains("Snapshot") || $0.contains("Gallery") || $0.contains("Window.swift") }.isEmpty)
        let text = try Self.sourceFiles().map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(!text.contains("NSWindow"))
        #expect(!text.contains("NSBitmapImageRep"))
    }

    @Test("The policy finds a private selector and an underscored key path")
    func policyFindsViolations() {
        let samples = [
            #"@objc func _hasKeyAppearance() -> Bool"#, #".environment(\._colorSchemeContrast, .increased)"#,
        ]
        for sample in samples {
            #expect(
                Self.forbiddenPatterns.contains { sample.range(of: $0.pattern, options: .regularExpression) != nil })
        }
    }
}
