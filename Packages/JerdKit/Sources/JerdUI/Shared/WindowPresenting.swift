/// Brings the main window to the front, and opens it when it is closed. JerdLive implements it
/// with the SwiftUI `openWindow` action and app activation.
@MainActor
public protocol WindowPresenting: AnyObject {
    func showMainWindow()
}
