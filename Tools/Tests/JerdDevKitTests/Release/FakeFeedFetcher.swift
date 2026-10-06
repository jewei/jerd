import Foundation
import os

@testable import JerdDevKit

/// Serves queued answers for the public feed URL, then repeats the last one. It records each URL.
final class FakeFeedFetcher: FeedFetching {
    private let state: OSAllocatedUnfairLock<(answers: [Data?], urls: [URL])>

    /// - Parameter answers: the bytes of each fetch; nil fails the fetch.
    init(_ answers: [Data?]) { state = OSAllocatedUnfairLock(initialState: (answers, [])) }

    func feed(at url: URL) async throws -> Data {
        let answer = state.withLock { state -> Data? in
            state.urls.append(url)
            return state.answers.count > 1 ? state.answers.removeFirst() : state.answers.first ?? nil
        }
        guard let answer else { throw DevFailure.checkFailed("offline") }
        return answer
    }

    var urls: [URL] { state.withLock { $0.urls } }
}
