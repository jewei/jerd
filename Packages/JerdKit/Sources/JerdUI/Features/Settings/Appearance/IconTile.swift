import AppKit
import JerdDesign
import SwiftUI

/// One selectable icon design in the icon picker.
struct IconTile: View {
    static let imageSide: CGFloat = 64

    let choice: AppIconChoice
    let image: NSImage?
    let isSelected: Bool
    let select: @MainActor () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: select) {
            VStack(spacing: Spacing.small) {
                artwork
                Text(choice.title)
                    .font(TextRole.detail.font.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.large)
            .padding(.horizontal, Spacing.small)
            .background { shape.fill(fill) }
            .overlay { shape.strokeBorder(stroke, lineWidth: isSelected ? 2 : 1) }
            .overlay(alignment: .topTrailing) { checkmark }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityIdentifier.make("appearance", "icon", choice.rawValue))
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: Radius.iconTile(side: Self.imageSide), style: .continuous)
                    .fill(.quaternary)
            }
        }
        .frame(width: Self.imageSide, height: Self.imageSide)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var checkmark: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(Spacing.small)
                .accessibilityHidden(true)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
    }

    private var fill: Color {
        isSelected ? Color.accentColor.opacity(Opacity.bannerFill) : Color.primary.opacity(Opacity.cardFill)
    }

    private var stroke: Color {
        if isSelected { return Color.accentColor }
        let opacity = contrast == .increased ? Opacity.tintStrokeIncreasedContrast : Opacity.tintStroke
        return Color.secondary.opacity(opacity)
    }
}
