import Foundation
import JerdUI
import Testing

/// `Docs/Reference.md` names every defaults key and icon value of the compatibility contract.
@Suite struct AppearanceDefaultsReferenceTests {
    /// The repository copy of the data reference, found from this source file.
    private static func reference() throws -> String {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { folder.deleteLastPathComponent() }
        return try String(contentsOf: folder.appendingPathComponent("Docs/Reference.md"), encoding: .utf8)
    }

    @Test func theReferenceNamesEveryDefaultsKeyAndIconValue() throws {
        let text = try Self.reference()
        let keys = [AppearanceDefaults.showMenuBarKey, AppearanceDefaults.showDockKey, AppearanceDefaults.appIconKey]
        let names = keys + AppIconChoice.allCases.map(\.rawValue)
        let missing = names.filter { !text.contains("`\($0)`") }
        #expect(missing.isEmpty, "Docs/Reference.md does not name: \(missing)")
    }
}
