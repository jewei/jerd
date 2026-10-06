import Foundation
import ObjectiveC
import Testing

@testable import JerdSystem

/// Pins the XPC selectors and their full type encodings to the values of the old `JerdCore` protocols.
@Suite struct HelperWireProtocolTests {
    private typealias MethodTypeEncoding = @convention(c) (Protocol, Selector, Bool, Bool) -> UnsafePointer<CChar>?

    /// Selector → extended type encoding (block argument classes included), sorted by selector.
    private func methods(of proto: Protocol) throws -> [String: String] {
        let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_protocol_getMethodTypeEncoding"))
        let encoding = unsafeBitCast(symbol, to: MethodTypeEncoding.self)
        var count: UInt32 = 0
        let list = try #require(protocol_copyMethodDescriptionList(proto, true, true, &count))
        defer { free(list) }
        var result: [String: String] = [:]
        for index in 0..<Int(count) {
            let selector = try #require(list[index].name)
            result[NSStringFromSelector(selector)] = encoding(proto, selector, true, true).map { String(cString: $0) }
        }
        return result
    }

    @Test func helperSelectorsAndTypesMatchTheInstalledHelper() throws {
        let expected = [
            "acquireListenersWithReply:": "v24@0:8@?<v@?@\"NSFileHandle\"@\"NSFileHandle\"@\"NSString\">16",
            "configureSite:reply:": "v32@0:8@\"NSData\"16@?<v@?@\"NSString\">24",
            "recoverSetup:reply:": "v32@0:8@\"NSData\"16@?<v@?@\"NSString\">24",
            "releaseListenersWithReply:": "v24@0:8@?<v@?>16",
            "removeSetupWithReply:": "v24@0:8@?<v@?@\"NSString\">16",
            "statusWithReply:": "v24@0:8@?<v@?@\"NSData\"@\"NSString\">16",
        ]
        #expect(try methods(of: (any JerdHelperProtocol).self) == expected)
        #expect(HelperWireProtocol.helperSelectors == expected.keys.sorted())
    }

    @Test func consentSelectorAndTypeMatchTheInstalledApp() throws {
        let expected = ["changeTrust:reply:": "v32@0:8@\"NSData\"16@?<v@?i>24"]
        #expect(try methods(of: (any JerdTrustConsentProtocol).self) == expected)
        #expect(HelperWireProtocol.consentSelectors == expected.keys.sorted())
    }

    @Test func payloadLimitsAreStrict() throws {
        let approval = SystemRecoveryApproval(recordID: String(repeating: "a", count: 64), action: .removeSetup)
        let data = try HelperWireProtocol.encode(approval)
        #expect(try HelperWireProtocol.decode(SystemRecoveryApproval.self, from: data, limit: 4_096) == approval)
        #expect(throws: (any Error).self) {
            try HelperWireProtocol.decode(SystemRecoveryApproval.self, from: data, limit: data.count)
        }
        #expect(throws: (any Error).self) {
            try HelperWireProtocol.decode(SystemRecoveryApproval.self, from: Data("{}".utf8), limit: 4_096)
        }
        #expect(HelperWireProtocol.configureLimit == 131_072)
        #expect(HelperWireProtocol.recoverLimit == 4_096)
        #expect(HelperWireProtocol.consentLimit == 131_072)
    }

    @Test func theLaunchdPlistIsUnchanged() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let plist = try String(
            contentsOf: root.appendingPathComponent("Apps/JerdHelper/dev.jerd.helper.plist"), encoding: .utf8)
        #expect(
            plist == """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>Label</key><string>dev.jerd.helper</string>
                    <key>BundleProgram</key><string>Contents/Library/LaunchServices/JerdHelper</string>
                    <key>MachServices</key><dict><key>dev.jerd.helper</key><true/></dict>
                    <key>AssociatedBundleIdentifiers</key><array><string>dev.jerd.app</string></array>
                </dict>
                </plist>

                """)
    }

    @Test func serviceNamesAndPathsAreStable() {
        #expect(HelperServiceIdentity.machServiceName == "dev.jerd.helper")
        #expect(HelperServiceIdentity.plistName == "dev.jerd.helper.plist")
        #expect(HelperServiceIdentity.appIdentifier == "dev.jerd.app")
        #expect(HelperServiceIdentity.helperIdentifier == "dev.jerd.helper")
        #expect(HelperServiceIdentity.recordDirectory.path == "/Library/Application Support/JerdHelper")
        #expect(HelperServiceIdentity.hostsFile.path == "/private/etc/hosts")
        #expect(HelperServiceIdentity.bundleProgram == "Contents/Library/LaunchServices/JerdHelper")
    }
}
