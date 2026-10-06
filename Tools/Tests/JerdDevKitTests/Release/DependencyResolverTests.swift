import Foundation
import Testing

@testable import JerdDevKit

@Suite("Payload dependency resolution")
struct DependencyResolverTests {
    static let payload = URL(filePath: "/p/mysql")
    static let files: Set<String> = ["/p/mysql/bin/mysqld", "/p/mysql/lib/libssl.3.dylib", "/p/mysql/lib/plugin/x.so"]

    static let resolver = DependencyResolver(payload: payload) { files.contains($0.path) }
    static let binary = URL(filePath: "/p/mysql/bin/mysqld")

    @Test("System libraries need no file")
    func systemLibraries() throws {
        #expect(try Self.resolver.resolve("/usr/lib/libSystem.B.dylib", of: Self.binary, rpaths: []) == nil)
        #expect(
            try Self.resolver.resolve("/System/Library/Frameworks/A.framework/A", of: Self.binary, rpaths: []) == nil)
    }

    @Test("Loader, run-path, and payload library references resolve inside the payload")
    func bundledLibraries() throws {
        let ssl = URL(filePath: "/p/mysql/lib/libssl.3.dylib")
        #expect(try Self.resolver.resolve("@loader_path/../lib/libssl.3.dylib", of: Self.binary, rpaths: []) == ssl)
        #expect(
            try Self.resolver.resolve("@rpath/libssl.3.dylib", of: Self.binary, rpaths: ["@loader_path/../lib"]) == ssl)
        #expect(try Self.resolver.resolve("@rpath/libssl.3.dylib", of: Self.binary, rpaths: []) == ssl)
        let plugin = URL(filePath: "/p/mysql/lib/plugin/x.so")
        #expect(try Self.resolver.resolve("@loader_path/../libssl.3.dylib", of: plugin, rpaths: []) == ssl)
    }

    @Test("Homebrew paths, paths outside the payload, and missing files are refused")
    func refusals() {
        for dependency in [
            "/opt/homebrew/opt/xz/lib/liblzma.5.dylib", "@loader_path/../../other/libssl.3.dylib",
            "@rpath/libnone.dylib",
            "libbare.dylib",
        ] {
            #expect(throws: DevFailure.self) { try Self.resolver.resolve(dependency, of: Self.binary, rpaths: []) }
        }
    }
}
