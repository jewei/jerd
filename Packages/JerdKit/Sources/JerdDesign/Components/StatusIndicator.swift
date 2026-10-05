import SwiftUI

/// A compact status symbol for sidebar rows and tables. The label shows as a tooltip and is
/// spoken by VoiceOver.
public struct StatusIndicator: View {
    private let status: DisplayStatus
    private let accessibilitySubject: String

    /// - Parameter accessibilityLabel: The subject of the status, for example "Site status".
    public init(_ status: DisplayStatus, accessibilityLabel: String) {
        self.status = status
        self.accessibilitySubject = accessibilityLabel
    }

    public var body: some View {
        StatusSymbol(tone: status.tone)
            .font(.callout)
            .frame(width: 16, height: 16)
            .help(status.label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySubject)
            .accessibilityValue(status.label)
    }
}
