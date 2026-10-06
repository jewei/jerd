import Testing

@testable import JerdWeb

@Suite struct HostsConflictCheckTests {
    @Test(arguments: [
        ("127.0.0.1 shop.test # another tool", true),
        ("10.0.0.2 alias SHOP.test", true),
        ("# shop.test\n127.0.0.1 other.test", false),
        ("# BEGIN JERD\n127.0.0.1 shop.test\n# END JERD", false),
        // The helper never writes `::1` and refuses such a section (shared rule).
        ("# BEGIN JERD\n::1 shop.test\n# END JERD", true),
        ("# BEGIN JERD\n10.1.1.1 shop.test\n# END JERD", true),
        ("# BEGIN JERD\n127.0.0.1 x.test\n# END JERD\n127.0.0.1 shop.test", true),
        ("127.0.0.1\tother.test\tshop.test", true),
        ("shop.test", false),
        ("127.0.0.1 shop.test.example", false),
        ("127.0.0.1 x.test #shop.test", false),
        ("# BEGIN JERD\r\n127.0.0.1 shop.test\r\n# END JERD", false),
        (" # BEGIN JERD\n127.0.0.1 shop.test\n# END JERD", true),
    ])
    func hostsConflictsFollowTheOwnedSectionAndTheAddress(_ text: String, _ conflict: Bool) {
        #expect(HostsConflictCheck.hasConflict(hostname: "shop.test", hostsText: text) == conflict)
    }

    @Test func theHostnameIsComparedWithoutCase() {
        #expect(HostsConflictCheck.hasConflict(hostname: "SHOP.test", hostsText: "10.0.0.1 shop.TEST"))
    }
}
