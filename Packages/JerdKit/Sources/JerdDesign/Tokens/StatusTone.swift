import SwiftUI

/// The five kinds of state that Jerd shows. Each tone has its own color and its own symbol
/// shape, so state never depends on color alone.
public enum StatusTone: String, CaseIterable, Hashable, Sendable {
    /// Running and verified.
    case ready
    /// Work is in progress, for example starting or stopping.
    case busy
    /// Stopped, disabled, or not set up. Nothing is wrong.
    case idle
    /// The user must act, for example to approve a setup step.
    case attention
    /// An operation failed.
    case failed

    public var color: Color {
        switch self {
        case .ready: .green
        case .busy: .blue
        case .idle: .gray
        case .attention: .orange
        case .failed: .red
        }
    }

    /// A filled symbol with a distinct outline shape for each tone.
    public var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .busy: "clock.fill"
        case .idle: "stop.circle"
        case .attention: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    /// Busy state shows a spinner instead of its symbol, unless Reduce Motion is on.
    public var showsProgress: Bool { self == .busy }

    /// The tone of a managed service. A failure wins over work in progress, and work in
    /// progress wins over the running state.
    public static func service(running: Bool, busy: Bool, failed: Bool) -> StatusTone {
        if failed { return .failed }
        if busy { return .busy }
        return running ? .ready : .idle
    }
}
