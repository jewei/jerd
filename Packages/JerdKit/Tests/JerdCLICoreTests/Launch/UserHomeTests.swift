import Foundation
import Testing

@testable import JerdCLICore

@Suite struct UserHomeTests {
    private static let account = URL(fileURLWithPath: "/Users/account", isDirectory: true)

    @Test(arguments: [
        ("/tmp/fake home", "/tmp/fake home"),
        ("/Users/u/", "/Users/u"),
        ("/Users/u//./", "/Users/u"),
    ])
    func absoluteHomeWinsAsInTheShell(home: String, expected: String) {
        #expect(UserHome.resolve(home: Array(home.utf8), account: Self.account).path == expected)
    }

    @Test(arguments: [nil, [], Array("relative/home".utf8), [0x2F, 0xFF]] as [[UInt8]?])
    func unusableHomeGivesTheAccountHome(home: [UInt8]?) {
        #expect(UserHome.resolve(home: home, account: Self.account) == Self.account)
    }

    @Test func dataRootIsBelowTheHome() {
        let layout = UserHome.dataLayout(home: URL(fileURLWithPath: "/tmp/h", isDirectory: true))
        #expect(layout.binDirectory.path == "/tmp/h/Library/Application Support/Jerd/bin")
    }
}
