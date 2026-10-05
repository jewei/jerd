import SwiftUI

/// The meaning of an inline message. Each kind has its own symbol and a spoken name, so the
/// meaning does not depend on color alone.
public enum MessageKind: String, CaseIterable, Hashable, Sendable {
    case info
    case success
    case warning
    case error

    public var color: Color {
        switch self {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    public var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    /// The word that VoiceOver reads before the message text.
    public var spokenName: String {
        switch self {
        case .info: "Information"
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    /// Warnings and errors are announced when they appear, because they need action.
    public var isAnnounced: Bool {
        self == .warning || self == .error
    }
}
