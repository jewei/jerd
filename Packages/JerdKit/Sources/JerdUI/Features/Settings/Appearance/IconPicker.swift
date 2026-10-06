import JerdDesign
import SwiftUI

/// The grid of icon designs. The selected tile has an accent outline and a checkmark; VoiceOver
/// reads each tile as a selectable button.
struct IconPicker: View {
    @Bindable var model: AppearanceModel
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: Spacing.medium)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.medium) {
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
