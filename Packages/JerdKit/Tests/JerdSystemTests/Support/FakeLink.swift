import Foundation
import JerdFoundation
import os

@testable import JerdSystem

struct FakeLink: HelperLink {
    let helper: FakeHelper

    func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any JerdHelperProtocol)? {
        guard helper.script.withLock({ $0.transportFailure }) else { return helper }
        onError(NSError(domain: NSCocoaErrorDomain, code: 4_097))
        return nil
    }

    func invalidate() {}
}
