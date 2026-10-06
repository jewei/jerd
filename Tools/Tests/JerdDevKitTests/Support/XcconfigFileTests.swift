import Testing

@testable import JerdDevKit

@Suite("Xcconfig file")
struct XcconfigFileTests {
    static let version = """
        // The app version. `./dev release` reads and changes only this file.
        MARKETING_VERSION = 0.1.0
        CURRENT_PROJECT_VERSION = 2

        """

    @Test("Reads plain values without comments and semicolons")
    func readsValues() throws {
        let file = XcconfigFile(path: "V.xcconfig", text: "A = 1 // note\nB=two;\n#include \"Base.xcconfig\"\n")
        #expect(try file.value(of: "A") == "1")
        #expect(try file.value(of: "B") == "two")
    }

    @Test("Changing a value changes only its line")
    func changesOneLine() throws {
        var file = XcconfigFile(path: "V.xcconfig", text: Self.version)
        try file.set("MARKETING_VERSION", to: "0.2.0")
        #expect(file.text == Self.version.replacingOccurrences(of: "0.1.0", with: "0.2.0"))
        #expect(try file.value(of: "CURRENT_PROJECT_VERSION") == "2")
    }

    @Test("Refuses a missing, repeated, or conditional setting")
    func refusesAmbiguousSettings() {
        #expect(throws: DevFailure.self) { try XcconfigFile(path: "V", text: "A = 1").value(of: "B") }
        #expect(throws: DevFailure.self) { try XcconfigFile(path: "V", text: "A = 1\nA = 2").value(of: "A") }
        #expect(throws: DevFailure.self) {
            try XcconfigFile(path: "V", text: "A = 1\nA[config=Release] = 2").value(of: "A")
        }
    }

    @Test("Refuses a value that would change other lines")
    func refusesUnsafeValues() {
        var file = XcconfigFile(path: "V", text: "A = 1")
        for value in ["", "1\nB = 2", "1 // x", "1;"] {
            #expect(throws: DevFailure.self) { try file.set("A", to: value) }
        }
    }

    @Test("Comments and includes are not settings")
    func ignoresOtherLines() {
        #expect(XcconfigFile.parse("// A = 1") == nil)
        #expect(XcconfigFile.parse("#include \"A=1\"") == nil)
        #expect(XcconfigFile.parse("9A = 1") == nil)
        #expect(XcconfigFile.parse("A[sdk=macosx*] = 1")?.condition == "sdk=macosx*")
    }
}
