import Testing

@testable import JerdDevKit

@Suite("Runtime group selection")
struct RuntimeSelectionTests {
    @Test("No argument selects every group and XZ")
    func selectsAll() throws {
        #expect(try RuntimeSelection.parse([]) == .all)
    }

    @Test("Storage always builds XZ, because RustFS needs it")
    func storageNeedsXZ() throws {
        #expect(try RuntimeSelection.parse(["storage"]) == RuntimeSelection(groups: [.storage], buildsXZ: true))
        #expect(try RuntimeSelection.parse(["Mail"]) == RuntimeSelection(groups: [.mail], buildsXZ: false))
    }

    @Test("Names are case-insensitive, keep the group order, and accept Support/XZ")
    func parsesNames() throws {
        let selection = try RuntimeSelection.parse(["Mail", "Development", "Support/XZ", "mail"])
        #expect(selection == RuntimeSelection(groups: [.development, .mail], buildsXZ: true))
        #expect(try RuntimeSelection.parse(["xz"]) == RuntimeSelection(groups: [], buildsXZ: true))
    }

    @Test("An unknown name is a usage error that lists the valid names")
    func refusesUnknown() {
        #expect(
            throws: DevFailure.usage(
                "Unknown runtime group \"cache\". Use one or more of: development, database, mail, storage, xz.")
        ) { try RuntimeSelection.parse(["cache"]) }
    }
}
