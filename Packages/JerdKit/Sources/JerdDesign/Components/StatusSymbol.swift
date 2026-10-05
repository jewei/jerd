import SwiftUI

/// The symbol of a status tone, or a small spinner for busy work. It has no accessibility
/// element of its own; the owning badge or indicator speaks the status.
struct StatusSymbol: View {
    let tone: StatusTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if tone.showsProgress && !reduceMotion {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: tone.systemImage)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tone.color)
            }
        }
        .accessibilityHidden(true)
    }
}
