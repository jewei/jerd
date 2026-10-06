import Foundation
import os

@testable import JerdDevKit

/// A server that serves nothing and records its starts and stops.
final class FakeFileServer: LoopbackFileServing {
    static let base = URL(string: "http://127.0.0.1:1234/")!

    private let state = OSAllocatedUnfairLock(initialState: (started: [URL](), stops: 0))

    func start(serving folder: URL) async throws -> URL {
        state.withLock { $0.started.append(folder) }
        return Self.base
    }

    func stop() async {
        state.withLock { $0.stops += 1 }
    }

    var started: [URL] { state.withLock { $0.started } }
    var stops: Int { state.withLock { $0.stops } }
}
