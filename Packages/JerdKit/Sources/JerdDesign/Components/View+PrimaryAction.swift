import SwiftUI

extension View {
    /// Uses the prominent style only for an enabled primary action, so a disabled control
    /// never looks like the next step.
    @ViewBuilder
    public func primaryActionStyle(isPrimary: Bool = true, isEnabled: Bool) -> some View {
        if isPrimary && isEnabled {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered).disabled(!isEnabled)
        }
    }
}
