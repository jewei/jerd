import Foundation
import JerdFoundation
import JerdSystem
import Testing

@testable import JerdHelperCore

@Suite struct ConsentRequesterTests {
    private final class App: NSObject, JerdTrustConsentProtocol, Sendable {
        let status: Int32
        let twice: Bool
        init(status: Int32, twice: Bool = false) {
            self.status = status
            self.twice = twice
        }

        func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void) {
            reply(status)
            if twice { reply(-1) }
        }
    }

    private let request = TrustConsentRequest(certificateDER: Data([1]), hostnames: ["a.test"], policy: .serverTLS)

    @Test func returnsTheFirstStatusOfTheApp() async throws {
        let requester = ConsentRequester { _ in .open(App(status: 0, twice: true)) }
        #expect(try await requester.change(request) == 0)
    }

    @Test func aClosedConnectionInterruptsTheApproval() async {
        let requester = ConsentRequester { _ in .closed }
        await #expect(throws: JerdError.approvalInterrupted("The app connection closed before certificate approval.")) {
            try await requester.change(request)
        }
    }

    @Test func aMissingInterfaceInterruptsTheApproval() async {
        let requester = ConsentRequester { _ in .unavailable }
        await #expect(throws: JerdError.approvalInterrupted("The certificate consent interface is unavailable.")) {
            try await requester.change(request)
        }
    }

    @Test func aTransportErrorDuringTheCallInterruptsTheApproval() async {
        let requester = ConsentRequester { onError in
            onError(NSError(domain: NSCocoaErrorDomain, code: 4_097, userInfo: [NSLocalizedDescriptionKey: "gone"]))
            return .open(App(status: 0))
        }
        await #expect(
            throws: JerdError.approvalInterrupted("The app connection closed during certificate approval: gone")
        ) {
            try await requester.change(request)
        }
    }
}
