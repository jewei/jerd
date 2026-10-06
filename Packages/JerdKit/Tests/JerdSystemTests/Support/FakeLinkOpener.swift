import Foundation
import JerdFoundation
import os

@testable import JerdSystem

/// Opens fake links to one `FakeHelper` and counts them.
final class FakeLinkOpener: HelperLinkOpening, Sendable {
    let helper: FakeHelper
    let opened = OSAllocatedUnfairLock(initialState: 0)
    let closeHandlers = OSAllocatedUnfairLock(initialState: [@Sendable () -> Void]())

    init(_ helper: FakeHelper) { self.helper = helper }

    func open(exporting responder: ConsentResponder, onClose: @escaping @Sendable () -> Void) throws -> any HelperLink {
        opened.withLock { $0 += 1 }
        closeHandlers.withLock { $0.append(onClose) }
        helper.responder.withLock { $0 = responder }
        return FakeLink(helper: helper)
    }
}
