import AppKit

/// The Quit command of the app menu and the menu bar item.
///
/// AppKit drops `terminate(_:)` without a call to `applicationShouldTerminate` while a window
/// shows a sheet, so ⌘Q did nothing while, for example, the HTTPS approval sheet was open (found
/// in the live run of WP12). Quit first ends every open sheet, which is the sheet's Cancel, then
/// asks AppKit to terminate, which starts the staged quit.
@MainActor
public enum ApplicationQuit {
    public static func request() {
        endSheets(in: NSApp.windows)
        NSApp.terminate(nil)
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
