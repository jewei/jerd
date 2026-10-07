@testable import JerdLive

/// Counts the requests to open Login Items; System Settings never opens.
actor RecordingLoginItems: LoginItemsOpening {
    private(set) var openCount = 0

    func openLoginItems() { openCount += 1 }
}
