import AppKit

/// Every quit path of Jerd: the app menu, the menu bar item, the quit Apple Event (Dock,
/// logout, restart, shutdown; `QuitAppleEventHandler`), and a Sparkle relaunch.
///
/// AppKit drops `terminate(_:)` without a call to `applicationShouldTerminate` while a window
/// shows a sheet, so ⌘Q did nothing while, for example, the HTTPS approval sheet was open. Quit
/// first ends every open sheet, which is the sheet's Cancel, then asks AppKit to terminate, which
/// starts the staged quit.
@MainActor
public enum ApplicationQuit {
    public static func request() {
        endOpenSheets()
        NSApp.terminate(nil)
    }

    /// Ends every open sheet of the app. Sparkle calls `terminate(_:)` itself right after its
    /// `updaterWillRelaunchApplication` delegate call, so the updater calls only this.
    public static func endOpenSheets() {
        endSheets(in: NSApp.windows)
    }

    /// Ends each sheet, innermost first, so the windows accept termination.
    package static func endSheets(in windows: [any SheetHosting]) {
        for window in windows {
            while let sheet = innermostSheet(of: window), let host = sheet.sheetHost {
                host.endHostedSheet(sheet)
            }
        }
    }

    private static func innermostSheet(of window: any SheetHosting) -> (any SheetHosting)? {
        var sheet = window.hostedSheet
        while let nested = sheet?.hostedSheet { sheet = nested }
        return sheet
    }
}
