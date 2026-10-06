import AppKit

/// Handles the quit Apple Event that the Dock menu, logout, restart, and shutdown send.
///
/// AppKit's own handler calls `terminate(_:)`, which AppKit drops while a window shows a sheet,
/// so the Dock Quit did nothing and a logout reported that Jerd stopped it. This handler runs
/// `ApplicationQuit.request()` instead: it ends every open sheet first, then starts the staged
/// quit. `LiveApp.installQuitEventHandler()` installs it.
@MainActor
package final class QuitAppleEventHandler: NSObject {
    private let manager: NSAppleEventManager
    private let request: @MainActor () -> Void

    /// - Parameters:
    ///   - manager: The event manager of the process.
    ///   - request: The quit to run; tests pass a recorder.
    package init(manager: NSAppleEventManager, request: @escaping @MainActor () -> Void) {
        self.manager = manager
        self.request = request
        super.init()
    }

    /// Replaces AppKit's quit handler. The event manager does not retain the handler, so keep
    /// this object for the lifetime of the app.
    package func install() {
        manager.setEventHandler(
            self, andSelector: #selector(handleQuit(_:withReply:)), forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication))
    }

    /// Gives the quit event back to no handler; tests use it to leave the process as it was.
    package func remove() {
        manager.removeEventHandler(
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    /// The event manager calls this on the main thread.
    @objc private nonisolated func handleQuit(
        _ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor
    ) {
        MainActor.assumeIsolated { request() }
    }
}
