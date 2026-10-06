import Foundation
import Testing

@testable import JerdTunnels

/// `Docs/Reference.md` names the Keychain service of the tunnel tokens.
@Suite struct TunnelKeychainReferenceTests {
    @Test func theReferenceNamesTheTokenService() throws {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { folder.deleteLastPathComponent() }
        let text = try String(contentsOf: folder.appendingPathComponent("Docs/Reference.md"), encoding: .utf8)
        #expect(text.contains("`\(TunnelKeychainItem.tokenService)`"))
    }
}
