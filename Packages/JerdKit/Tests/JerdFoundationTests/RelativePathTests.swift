import Foundation
import JerdFoundation
import Testing

@Suite struct RelativePathTests {
    @Test(arguments: ["bin/php", "a", "vendor/laravel/installer/bin/laravel", "dir/.hidden", "a b/ü"])
    func strictPathsAccepted(_ text: String) throws {
        #expect(try #require(RelativePath(text)).string == text)
    }

    @Test(arguments: ["", "/etc/passwd", "a//b", "./a", "a/.", "../a", "a/../b", "a\\b", "a/\u{7}", "a/", "a\nb"])
    func unsafeStrictPathsRefused(_ text: String) {
        #expect(RelativePath(text) == nil)
    }

    @Test(arguments: [("./root//bin/", "root/bin"), ("root/./x", "root/x"), ("a", "a")])
    func archiveNamesAreNormalized(_ text: String, _ expected: String) throws {
        #expect(try #require(RelativePath(normalizing: text)).string == expected)
    }

    @Test(arguments: ["../escape", "/absolute", "a/../b", ".", "./", "", "a\\b", "a\u{0}b"])
    func unsafeArchiveNamesRefused(_ text: String) {
        #expect(RelativePath(normalizing: text) == nil)
    }

    @Test func pathsResolveInsideTheirFolderAndCodeAsText() throws {
        let path = try #require(RelativePath("bin/php"))
        #expect(path.url(in: URL(fileURLWithPath: "/runtime")).path == "/runtime/bin/php")
        let suffix = try #require(RelativePath("x"))
        #expect(path.appending(suffix).string == "bin/php/x")
        #expect(try JSONDecoder().decode([RelativePath].self, from: JSONEncoder().encode([path])) == [path])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([RelativePath].self, from: Data("[\"../x\"]".utf8))
        }
    }
}
