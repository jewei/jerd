import Foundation
import JerdProcess
import Testing

@Suite struct ProcessRequestTests {
    @Test func defaultsAreEmptyAndExplicit() {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/true"), workingDirectory: URL(fileURLWithPath: "/"))
        #expect(request.arguments.isEmpty)
        #expect(request.environment.isEmpty)
        #expect(request.listeners == nil)
        #expect(request.redactedValues.isEmpty)
    }
}
