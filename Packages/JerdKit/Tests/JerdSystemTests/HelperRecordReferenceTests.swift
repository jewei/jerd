import Foundation
import JerdSystem
import Testing

/// `Docs/Reference.md` names the helper record folder and every record file.
@Suite struct HelperRecordReferenceTests {
    /// The repository copy of the data reference, found from this source file.
    private static func reference() throws -> String {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { folder.deleteLastPathComponent() }
        return try String(contentsOf: folder.appendingPathComponent("Docs/Reference.md"), encoding: .utf8)
    }

    @Test func theReferenceNamesEveryHelperRecordFile() throws {
        let text = try Self.reference()
        let names = RootRecordDirectory.File.allCases.map(\.rawValue) + [HelperServiceIdentity.recordDirectory.path]
        let missing = names.filter { !text.contains("`\($0)`") }
        #expect(missing.isEmpty, "Docs/Reference.md does not name: \(missing)")
    }
}
