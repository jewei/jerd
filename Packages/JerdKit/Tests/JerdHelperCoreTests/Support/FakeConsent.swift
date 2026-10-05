import Darwin
import Foundation
import JerdFoundation
import JerdSystem
import os

@testable import JerdHelperCore

/// The app side of consent: records requests and answers with a status or an interruption.
final class FakeConsent: ConsentRequesting, Sendable {
    enum Answer: Sendable {
        case status(Int32)
        case interrupted
    }

    let answer: OSAllocatedUnfairLock<Answer>
    let requests = OSAllocatedUnfairLock(initialState: [TrustConsentRequest]())
    let trusted = OSAllocatedUnfairLock(initialState: [Data: TrustConsentRequest]())

    init(_ answer: Answer = .status(0)) { self.answer = OSAllocatedUnfairLock(initialState: answer) }

    func change(_ request: TrustConsentRequest) async throws -> Int32 {
        requests.withLock { $0.append(request) }
        switch answer.withLock({ $0 }) {
        case .interrupted: throw JerdError.approvalInterrupted("The app connection closed before certificate approval.")
        case .status(let status):
            if status == 0 {
                trusted.withLock { $0[request.certificateDER] = request.hostnames == nil ? nil : request }
            }
            return status
        }
    }
}
