import AppKit

/// A window that can show a sheet. `NSWindow` is the live type; tests use a fake, because a
/// test process has no running app in which AppKit attaches sheets.
@MainActor
package protocol SheetHosting: AnyObject {
    var hostedSheet: (any SheetHosting)? { get }
    var sheetHost: (any SheetHosting)? { get }
    /// Ends `sheet` with the Cancel response.
    func endHostedSheet(_ sheet: any SheetHosting)
}

extension NSWindow: SheetHosting {
    package var hostedSheet: (any SheetHosting)? { attachedSheet }
    package var sheetHost: (any SheetHosting)? { sheetParent }

    package func endHostedSheet(_ sheet: any SheetHosting) {
        guard let sheet = sheet as? NSWindow else { return }
        endSheet(sheet, returnCode: .cancel)
    }
}
