import JerdProcess
import Testing

@Suite struct ListenerReportTests {
    @Test func processLinesAndNameLinesAreCollected() throws {
        let pids = try #require(ListenerReport.parse("p123\np456\n"))
        #expect(pids.processIDs == [123, 456])
        #expect(pids.addresses.isEmpty)
        let names = try #require(ListenerReport.parse("p123\nf5\nn127.0.0.1:3306\nf6\nn*:3306\nf7\nn[::1]:3306\n"))
        #expect(names.processIDs == [123])
        #expect(names.addresses == ["127.0.0.1:3306", "*:3306", "[::1]:3306"])
    }

    @Test func emptyOutputIsAnEmptyReport() {
        #expect(ListenerReport.parse("") == ListenerReport(processIDs: [], addresses: []))
    }

    @Test(arguments: ["pabc\n", "p0\n", "p-4\n"])
    func anInvalidProcessLineMakesTheReportUnknown(_ output: String) {
        #expect(ListenerReport.parse(output) == nil)
    }
}
