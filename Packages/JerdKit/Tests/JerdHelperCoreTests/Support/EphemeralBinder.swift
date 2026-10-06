import Darwin
import Foundation
import JerdFoundation
import JerdSystem
import os

@testable import JerdHelperCore

/// Binds ephemeral loopback ports instead of 80 and 443.
struct EphemeralBinder: ListenerBinding {
    func bindStandardPorts() throws -> LoopbackListenerPair { try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0) }
}
