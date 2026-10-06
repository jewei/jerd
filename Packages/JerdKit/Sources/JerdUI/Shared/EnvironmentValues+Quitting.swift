import SwiftUI

extension EnvironmentValues {
    /// True while the staged quit runs. The workspace sets it for every page, sidebar, toolbar,
    /// and sheet. A control that starts work reads it and turns off; Cancel and Close in a
    /// sheet never read it, so an open sheet can always close.
    @Entry public var isQuitting = false
}
