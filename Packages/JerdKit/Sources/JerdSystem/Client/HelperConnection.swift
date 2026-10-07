import Foundation
import JerdFoundation

/// The app's one cached link to the helper and the calls over it.
///
/// A link is opened on the first call, only while the daemon is enabled. Its invalidation, its
/// interruption, or a reply timeout drops it, but only if it is still the current link, so a late
/// event of an old link never drops a newer one. A reply timeout does not drop a link that carries a
/// call without a timeout (a change that can wait for macOS approval): dropping it would interrupt
/// that change. Transport errors become one stable message.
public actor HelperConnection {
    private let opener: any HelperLinkOpening
    private let responder: ConsentResponder
    private let isEnabled: @Sendable () -> Bool
    private var link: (id: UUID, link: any HelperLink)?
    /// The number of calls without a timeout that wait on each link.
    private var openChanges: [UUID: Int] = [:]

    public init(opener: any HelperLinkOpening, responder: ConsentResponder, isEnabled: @escaping @Sendable () -> Bool) {
        self.opener = opener
        self.responder = responder
        self.isEnabled = isEnabled
    }

    /// True while a link is open.
    public var isConnected: Bool { link != nil }

    /// Sends one request and waits for its result.
    ///
    /// - Parameter timeout: nil for calls that can wait for a macOS approval prompt.
    public func call<Value: Sendable>(
        timeout: Duration? = .seconds(20), cancellation: ReplyGate<Value>.CancellationPolicy = .awaitReply,
        _ send: @escaping @Sendable (any JerdHelperProtocol, ReplyGate<Value>) -> Void
    ) async throws -> Value {
        let (id, current) = try connect()
        if timeout == nil { openChanges[id, default: 0] += 1 }
        defer { if timeout == nil { endChange(on: id) } }
        let deliver: (ReplyGate<Value>) -> Void = { gate in
            let proxy = current.proxy { error in gate.resolve(.failure(Self.transportError(error))) }
            guard let proxy else {
                gate.resolve(.failure(JerdError.unavailable("The helper interface is unavailable.")))
                return
            }
            send(proxy, gate)
        }
        return try await ReplyGate<Value>.wait(
            cancellation: cancellation, timeout: timeout,
            onTimeout: { [weak self] in await self?.dropAfterTimeout(id) },
            send: deliver)
    }

    /// Closes the current link. The next call opens a new one.
    public func invalidate() {
        link?.link.invalidate()
        link = nil
    }

    /// Drops the link `id` if it is still current.
    func drop(_ id: UUID) {
        guard link?.id == id else { return }
        invalidate()
    }

    /// Drops the link `id` after a reply timeout, unless a change still waits on it.
    func dropAfterTimeout(_ id: UUID) {
        guard openChanges[id, default: 0] == 0 else { return }
        drop(id)
    }

    private func endChange(on id: UUID) {
        let remaining = openChanges[id, default: 1] - 1
        openChanges[id] = remaining > 0 ? remaining : nil
    }

    private func connect() throws -> (UUID, any HelperLink) {
        if let link { return (link.id, link.link) }
        guard isEnabled() else { throw JerdError.unavailable("Approved helper setup is required.") }
        let id = UUID()
        let opened = try opener.open(exporting: responder) { [weak self] in
            Task { await self?.drop(id) }
        }
        link = (id, opened)
        return (id, opened)
    }

    static func transportError(_ error: any Error) -> JerdError {
        let detail = error as NSError
        return .unavailable(
            "Jerd could not communicate with its system helper. Choose System setup → Reconnect helper… and approve "
                + "reconnection. Existing hosts and certificate settings will remain. (\(detail.domain) \(detail.code))"
        )
    }
}
