import JerdDesign
import JerdTunnels

/// The status of a tunnel connector as the user sees it.
public enum TunnelStatusPolicy {
    public static func status(_ state: TunnelState) -> DisplayStatus {
        switch state {
        case .connected: DisplayStatus(state.title, tone: .ready)
        case .starting, .connecting, .reconnecting, .stopping: DisplayStatus(state.title, tone: .busy)
        case .stopped: DisplayStatus(state.title, tone: .idle)
        case .failed: DisplayStatus(state.title, tone: .failed)
        }
    }
}
