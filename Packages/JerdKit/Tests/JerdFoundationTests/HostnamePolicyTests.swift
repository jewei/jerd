import Foundation
import JerdFoundation
import Testing

@Suite struct HostnamePolicyTests {
    private static let suffixMessage = "Use a hostname ending in .test, without spaces or a port."
    private static let labelMessage = "Use letters a–z, digits, and internal hyphens in hostname labels."

    @Test func validNamesAreReturnedInLowercase() throws {
        #expect(try HostnamePolicy.validate("SHOP.Example.test").value == "shop.example.test")
        #expect(try HostnamePolicy.validate("my-site2.test").value == "my-site2.test")
        #expect(try Hostname("a.test").description == "a.test")
    }

    @Test(arguments: [
        "test", "example.com", "foo.test:443", " foo.test", "foo.test.", "foo.test\n", "a/test",
        String(repeating: "a.", count: 124) + "a.test",
    ])
    func namesWithoutTheTestSuffixOrWithSpacesAreRefused(_ text: String) {
        #expect(throws: JerdError.invalid(Self.suffixMessage)) { try HostnamePolicy.validate(text) }
    }

    @Test(arguments: [
        "*.test", "-site.test", "site-.test", "foo..test", "café.test", "a_b.test", ".test",
        String(repeating: "a", count: 64) + ".test",
    ])
    func invalidLabelsAreRefused(_ text: String) {
        #expect(throws: JerdError.invalid(Self.labelMessage)) { try HostnamePolicy.validate(text) }
    }

    @Test func theLengthLimitsAreInclusive() throws {
        let label = String(repeating: "a", count: 63)
        #expect(try HostnamePolicy.validate(label + ".test").value == label + ".test")
        let longest = String(repeating: "a.", count: 123) + "aa.test"
        #expect(longest.utf8.count == 253)
        #expect(try HostnamePolicy.validate(longest).value == longest)
    }

    @Test func aSetHasOneTo256UniqueNamesAndIsSorted() throws {
        #expect(try HostnamePolicy.validateSet(["b.test", "A.test"]).map(\.value) == ["a.test", "b.test"])
        let range = JerdError.invalid("Select between 1 and 256 site hostnames for HTTPS setup.")
        #expect(throws: range) { try HostnamePolicy.validateSet([]) }
        let many = (0...256).map { "site\($0).test" }
        #expect(throws: range) { try HostnamePolicy.validateSet(many) }
        #expect(try HostnamePolicy.validateSet(Array(many.prefix(256))).count == 256)
        #expect(throws: JerdError.invalid("Each site needs a unique hostname.")) {
            try HostnamePolicy.validateSet(["shop.test", "SHOP.test"])
        }
    }

    @Test(arguments: [
        ("My Folder", "my-folder.test"), ("---", "project.test"), ("café", "cafe.test"),
        ("项目", "xiang-mu.test"), ("Ünïcode_Dir 2", "unicode-dir-2.test"), ("", "project.test"),
        (String(repeating: "x", count: 90), String(repeating: "x", count: 63) + ".test"),
    ])
    func suggestionsAreExactAndAlwaysValid(_ folder: String, _ expected: String) throws {
        let suggestion = HostnamePolicy.suggest(folderName: folder)
        #expect(suggestion.value == expected)
        #expect(try HostnamePolicy.validate(suggestion.value) == suggestion)
    }

    @Test func codingValidatesTheStoredText() throws {
        let encoded = try JSONEncoder().encode([try Hostname("shop.test")])
        #expect(String(decoding: encoded, as: UTF8.self) == "[\"shop.test\"]")
        #expect(try JSONDecoder().decode([Hostname].self, from: encoded).map(\.value) == ["shop.test"])
        #expect(throws: JerdError.self) { try JSONDecoder().decode([Hostname].self, from: Data("[\"x.com\"]".utf8)) }
    }
}
