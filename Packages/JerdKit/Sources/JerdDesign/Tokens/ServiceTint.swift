import SwiftUI

/// The tint of each area of Jerd, taken from the rainbow of the app icons. Use it only for
/// symbol tiles, never for status, so it cannot be read as a state.
public enum ServiceTint: String, CaseIterable, Hashable, Sendable {
    case sites
    case tunnels
    case databases
    case storage
    case mail
    case runtimes
    case appearance
    case neutral

    public var color: Color {
        switch self {
        case .sites: .blue
        case .tunnels: .cyan
        case .databases: .indigo
        case .storage: .teal
        case .mail: .pink
        case .runtimes: .brown
        case .appearance: .purple
        case .neutral: .gray
        }
    }
}
