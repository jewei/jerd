import Foundation

/// Checks the app that a build made, not only its sources: a conditional build setting, a target
/// setting in `project.yml`, or a command-line override can change the effective values.
/// - The built `Info.plist` has the pinned update feed URL and public key, the approved Sparkle
///   settings, the bundle identifier, and the minimum macOS version.
/// - Every executable of Jerd contains only arm64, because every bundled runtime is arm64 only.
enum BuiltAppPolicy {
    static let infoPlist = "Contents/Info.plist"
    static let executables = [
        "Contents/MacOS/Jerd", "Contents/MacOS/JerdCLI", "Contents/Library/LaunchServices/JerdHelper",
    ]
    static let architecture = "arm64"

    /// The Sparkle values after the build expands `$(JERD_UPDATE_FEED_URL)` and `$(JERD_UPDATE_PUBLIC_KEY)`,
    /// and the other values that installed copies depend on.
    static var requiredValues: [(key: String, value: SparkleInfoPlistPolicy.Value)] {
        let expanded: [String: SparkleInfoPlistPolicy.Value] = [
            "SUFeedURL": .string(UpdateSettingsPolicy.feedURL),
            "SUPublicEDKey": .string(UpdateSettingsPolicy.publicKey),
        ]
        let sparkle = SparkleInfoPlistPolicy.requiredValues.map { ($0.key, expanded[$0.key] ?? $0.value) }
        return sparkle + [
            ("CFBundleIdentifier", .string("dev.jerd.app")),
            ("LSMinimumSystemVersion", .string("14.0")),
        ]
    }

    /// - Parameter file: The path for the findings, relative to the repository root.
    static func infoPlistFindings(_ plistData: Data, file: String) -> [PolicyFinding] {
        let decoded = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        guard let dictionary = decoded as? [String: Any] else {
            return [PolicyFinding(file: file, message: "The file is not a property list dictionary.")]
        }
        let wrong = requiredValues.compactMap { key, required -> PolicyFinding? in
            let actual = dictionary[key].flatMap(SparkleInfoPlistPolicy.value(of:))
            guard actual != required else { return nil }
            let found = actual.map { "has \($0)" } ?? "is missing"
            return PolicyFinding(file: file, message: "\(key) \(found); it must be \(required).")
        }
        return wrong + SparkleInfoPlistPolicy.absentKeyFindings(dictionary, file: file)
    }

    /// - Parameter lipoOutput: The output of `lipo -archs`, or `nil` when lipo could not read the file.
    static func architectureFindings(file: String, lipoOutput: String?) -> [PolicyFinding] {
        guard let lipoOutput else {
            return [PolicyFinding(file: file, message: "lipo cannot read the architectures. Is the file missing?")]
        }
        let architectures = lipoOutput.split(whereSeparator: \.isWhitespace).map(String.init)
        guard architectures == [architecture] else {
            let found = architectures.joined(separator: " ")
            return [PolicyFinding(file: file, message: "The executable contains \(found); it must contain only arm64.")]
        }
        return []
    }
}
