import Foundation
import JerdFoundation
import JerdWeb

@testable import JerdLive

/// Answers a forwarded host apply with the one served site, nil for any other site, or an error,
/// and records each call.
actor FakeForwardedHostApplying: ForwardedHostApplying {
    private let served: Site?
    private var failure: JerdError?
    private(set) var requests: [UUID] = []

    init(serving site: Site? = nil) {
        served = site
    }

    func fail(_ error: JerdError) { failure = error }

    func applyForwardedHosts(servingSite siteID: UUID) throws -> Site? {
        requests.append(siteID)
        if let failure { throw failure }
        return served?.id == siteID ? served : nil
    }
}
