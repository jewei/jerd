import Foundation
import Testing

@testable import JerdUI

/// Reads the JerdUI sources and checks the copy rules of every literal button title: Title Case,
/// and one title for one action across pages.
@Suite("Button copy")
struct ButtonCopyTests {
    /// Words that Title Case keeps in lower case inside a title.
    private static let minorWords: Set<String> = [
        "a", "an", "and", "as", "at", "for", "in", "of", "on", "or", "the", "to",
    ]

    private static var sourcesFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JerdUI")
    }

    /// Every literal title of a `Button`, `PageAction`, `SheetConfirmation`, `SheetSecondaryAction`,
    /// and `FeatureAction` in the JerdUI sources.
    private static func buttonTitles() throws -> [String] {
        let enumerator = FileManager.default.enumerator(at: sourcesFolder, includingPropertiesForKeys: nil)
        let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        try #require(files.count > 100, "The JerdUI sources were not found at \(sourcesFolder.path)")
        let pattern = try Regex(
            #"(?:Button|PageAction|SheetConfirmation|SheetSecondaryAction)\(\s*"([^"\\]+)"|FeatureAction\([^)]*?title: "([^"\\]+)""#
        )
        var titles: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: pattern) {
                if let title = (match.output[1].substring ?? match.output[2].substring).map(String.init) {
                    titles.insert(title)
                }
            }
        }
        return titles.sorted()
    }

    @Test("Every literal button title uses Title Case")
    func titleCase() throws {
        let titles = try Self.buttonTitles()
        #expect(titles.count > 40)
        for title in titles {
            let words = title.split(separator: " ").map(String.init)
            for (index, word) in words.enumerated() {
                let isMinor = index > 0 && Self.minorWords.contains(word)
                let first = word.first.map(String.init) ?? ""
                #expect(
                    isMinor || first != first.lowercased() || !first.first!.isLetter || word.hasPrefix("."),
                    "\"\(title)\" is not Title Case at \"\(word)\"")
            }
        }
    }

    @Test("A button that only shows Runtimes is called View Runtimes or Manage Runtimes, never Runtimes")
    func runtimesLinkTitle() throws {
        #expect(try !Self.buttonTitles().contains("Runtimes"))
    }

    @Test("An empty sidebar section says why it is empty")
    func sidebarPlaceholder() {
        #expect(SidebarPlaceholder.text(for: .loading, items: "buckets", settings: "Storage") == "Loading buckets…")
        #expect(SidebarPlaceholder.text(for: .loaded, items: "services", settings: "Database") == "No services added")
        #expect(
            SidebarPlaceholder.text(for: .failed(message: "x"), items: "buckets", settings: "Storage")
                == "Storage settings could not be loaded")
    }
}
