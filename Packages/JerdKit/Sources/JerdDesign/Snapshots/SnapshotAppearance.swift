import AppKit
import SwiftUI

/// The system appearance that a snapshot uses. The raw value is part of the file name.
package enum SnapshotAppearance: String, CaseIterable, Sendable {
    case light
    case dark
    /// Light with Increase Contrast.
    case lightContrast = "light-contrast"
    /// Dark with Increase Contrast.
    case darkContrast = "dark-contrast"

    /// Every entry renders in these two; contrast variants are opt-in per entry.
    package static let standard: [SnapshotAppearance] = [.light, .dark]

    /// The AppKit appearance of the snapshot window, so AppKit controls match SwiftUI.
    package var appearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        case .lightContrast: .accessibilityHighContrastAqua
        case .darkContrast: .accessibilityHighContrastDarkAqua
        }
    }

    package var isIncreasedContrast: Bool {
        self == .lightContrast || self == .darkContrast
    }

    package var colorScheme: ColorScheme {
        switch self {
        case .light, .lightContrast: .light
        case .dark, .darkContrast: .dark
        }
    }
}
