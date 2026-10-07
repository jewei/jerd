import JerdDesign
import SwiftUI

/// The grid of icon designs. The selected tile has an accent outline and a checkmark; VoiceOver
/// reads each tile as a selectable button.
struct IconPicker: View {
    @Bindable var model: AppearanceModel
    /// One column per design, so the four tiles share the full width of the section.
    static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Spacing.medium), count: AppIconChoice.allCases.count)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: Spacing.medium) {
            ForEach(AppIconChoice.allCases) { choice in
                IconTile(
                    choice: choice, image: model.image(for: choice), isSelected: model.icon == choice
                ) {
                    model.icon = choice
                }
            }
        }
        .padding(.vertical, Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App icon")
    }
}
