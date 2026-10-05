import Testing

@testable import JerdHelperCore

@Suite struct ConnectionAcceptPolicyTests {
    @Test(arguments: [0, 1, 200, 500] as [UInt32])
    func refusesSystemAccounts(uid: UInt32) {
        #expect(ConnectionAcceptPolicy.decide(effectiveUserID: uid) == .reject(reason: "UID \(uid) is below 501"))
    }

    @Test(arguments: [501, 502, 65_000] as [UInt32])
    func acceptsRegularAccounts(uid: UInt32) {
        #expect(ConnectionAcceptPolicy.decide(effectiveUserID: uid) == .accept)
    }
}
