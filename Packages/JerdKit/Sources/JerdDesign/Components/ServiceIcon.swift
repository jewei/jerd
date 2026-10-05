import SwiftUI

/// A tinted rounded tile with an SF Symbol. It identifies an area of Jerd, never a state,
/// and is hidden from VoiceOver because a text title always comes next to it.
public struct ServiceIcon: View {
    /// The side length of the tile.
    public enum Size: CGFloat, CaseIterable, Sendable {
        case small = 28
        case medium = 36
        case large = 44
        case hero = 64
    }

    private let systemImage: String
    private let tint: Color
    private let size: Size
    @Environment(\.colorSchemeContrast) private var contrast

    public init(systemImage: String, tint: ServiceTint, size: Size = .medium) {
        self.init(systemImage: systemImage, color: tint.color, size: size)
    }

    public init(systemImage: String, color: Color, size: Size = .medium) {
        self.systemImage = systemImage
        self.tint = color
        self.size = size
    }

    public var body: some View {
        let side = size.rawValue
        let shape = RoundedRectangle(cornerRadius: Radius.iconTile(side: side), style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: (side * 0.46).rounded(), weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background { shape.fill(tint.opacity(Opacity.tintFill).gradient) }
            .overlay {
                shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var strokeOpacity: CGFloat {
        contrast == .increased ? Opacity.tintStrokeIncreasedContrast : Opacity.tintStroke
    }
}
