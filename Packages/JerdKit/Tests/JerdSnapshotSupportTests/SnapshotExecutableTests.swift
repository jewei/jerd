import Foundation
import Testing

/// Runs the built `jerd-snapshots` executable, because the settings that these tests prove
/// apply to a whole process before AppKit starts. `swift test` builds the executable with the
/// tests, in the same folder as the test bundle.
@Suite("Snapshot executable", .serialized)
struct SnapshotExecutableTests {
    /// Settings of a user who differs from the defaults in every way that changes drawing.
    private static let unusualUserSettings = [
        "-AppleAccentColor", "0", "-AppleHighlightColor", "1.000000 0.733333 0.721569 Red",
        "-AppleShowScrollBars", "Always", "-NSTableViewDefaultSizeMode", "3", "-AppleLocale", "fr_FR",
        "-AppleLanguages", "(fr)", "-AppleInterfaceStyle", "Dark",
    ]

    @Test("The accent color, scroll bar, sidebar, and region settings of the user do not change the images")
    func userSettingsDoNotChangeImages() throws {
        let pages = ["gallery-workspace", "gallery-rows"]
        let standard = try render(pages)
        let unusual = try render(Self.unusualUserSettings + pages)
        #expect(standard.status == 0)
        #expect(unusual.status == 0)
        #expect(!standard.files.isEmpty)
        #expect(standard.files.keys.sorted() == unusual.files.keys.sorted())
        for (name, data) in standard.files {
            #expect(unusual.files[name] == data, "\(name) depends on the user settings")
        }
    }

    @Test("Increase Contrast images come from a process with Increase Contrast on")
    func contrastImagesAreTruthful() throws {
        let result = try render(["gallery-cards"])
        #expect(result.status == 0)
        // The contrast pass refuses to write a file unless AppKit resolves the accessibility
        // appearance, so these files prove that the setting was on.
        let light = try #require(result.files["gallery-cards-light-panel.png"])
        let lightContrast = try #require(result.files["gallery-cards-light-contrast-panel.png"])
        let darkContrast = try #require(result.files["gallery-cards-dark-contrast-panel.png"])
        #expect(light != lightContrast)
        #expect(lightContrast != darkContrast)
    }

    private func render(_ arguments: [String]) throws -> (status: Int32, files: [String: Data]) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jerd-snapshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = Process()
        process.executableURL = try Self.executable()
        process.arguments = ["--output", folder.path(percentEncoded: false)] + arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var files: [String: Data] = [:]
        for name in names {
            files[name] = try Data(contentsOf: folder.appending(path: name))
        }
        return (process.terminationStatus, files)
    }

    private static func executable() throws -> URL {
        let url = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent().appending(path: "jerd-snapshots")
        try #require(
            FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)),
            "Build jerd-snapshots first: swift build --product jerd-snapshots")
        return url
    }
}

/// Finds the test bundle, whose folder also holds the built executables.
private final class BundleMarker {}
