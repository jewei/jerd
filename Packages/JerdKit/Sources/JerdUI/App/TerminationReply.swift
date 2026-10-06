/// The answer to one quit request, mapped by the app delegate to `NSApplication.TerminateReply`.
/// Every request gets exactly one reply: `later` replies once through the reply closure.
public enum TerminationReply: Equatable, Sendable {
    /// Terminate now. The services are already stopped.
    case now
    /// The staged quit runs. The reply closure receives the result.
    case later
    /// Do not terminate. A staged quit is already running and will reply for itself.
    case cancel
}
