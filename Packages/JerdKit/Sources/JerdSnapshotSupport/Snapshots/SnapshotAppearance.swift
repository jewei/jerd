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

    /// The appearance of the snapshot window. AppKit has no way to ask for Increase Contrast by
    /// name: `NSAppearance(named: .accessibilityHighContrastAqua)` returns plain Aqua. The
    /// contrast pass turns on Increase Contrast for the whole process instead.
    package var windowAppearanceName: NSAppearance.Name {
        colorScheme == .light ? .aqua : .darkAqua
    }

    /// The appearance that AppKit must resolve for the window, so the image shows what a user
    /// with these settings sees.
    package var resolvedAppearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        case .lightContrast: .accessibilityHighContrastAqua
        case .darkContrast: .accessibilityHighContrastDarkAqua
        }
    }

    /// The process contrast setting that this appearance needs.
    package var contrast: SnapshotContrast {
        self == .lightContrast || self == .darkContrast ? .increased : .standard
    }

    package var colorScheme: ColorScheme {
        switch self {
        case .light, .lightContrast: .light
        case .dark, .darkContrast: .dark
        }
    }
}
