import SwiftUI

extension View {
    /// Sets the accessibility identifier only when one is given, so a missing identifier never
    /// becomes an empty one.
    @ViewBuilder
    func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
