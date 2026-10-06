import JerdDesign
import SwiftUI

/// A switch on the trailing side, centered on its two-line label, as in System Settings. The
/// grouped form style puts the switch on the first line of a multi-line label. VoiceOver reads
/// the switch with the whole label, so it keeps the words that the user sees.
struct CenteredSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}
