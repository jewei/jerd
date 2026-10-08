import Foundation
import JerdFoundation

/// The app's only client of the privileged helper.
///
/// Timeouts: status, acquire, and release wait at most 20 seconds. Configure, remove, and recover
/// have no app timeout, because macOS can show an approval prompt for as long as the user needs.
/// Cancellation ends a status call at once; a call that changes state waits for its reply.
/// Each changing call opens its own consent scope for the reverse trust calls, then closes it.
public actor HelperClient {
    nonisolated let registration: HelperRegistration
    nonisolated let connection: HelperConnection
    nonisolated let gate: ConsentGate
    /// The one automatic restart of the helper in this app run (`HelperRecoveryPolicy`).
    var automaticRestart = AutomaticRestart.available
    /// True from a listener acquisition until their release, while sites can use the sockets.
    var holdsListeners = false
    /// The number of finished automatic restarts. A call compares it to see whether its link is
    /// older than a restart.
    var finishedRestarts = 0

    public init(
        registration: HelperRegistration = HelperRegistration(), opener: any HelperLinkOpening = XPCHelperLinkOpener(),
        gate: ConsentGate = ConsentGate(), trustSettings: any TrustSettingsApplying = AdminTrustSettings()
    ) {
        self.registration = registration
        self.gate = gate
        connection = HelperConnection(
            opener: opener, responder: ConsentResponder(gate: gate, settings: trustSettings),
            isEnabled: { registration.availability == .enabled })
    }

    /// The daemon state and, when it is enabled, the setup it reports.
    public func status() async throws -> HelperStatus {
        try await waitForRunningRestart()
        let availability = registration.availability
        guard availability == .enabled else { return HelperStatus(availability: availability, setup: .empty) }
        let connection = connection
        let data: Data = try await recovering {
            try await connection.call(cancellation: .readOnly) { proxy, gate in
                proxy.status { data, error in
                    if let data {
                        gate.resolve(.success(data))
                    } else {
                        gate.resolve(
                            .failure(error.map(HelperWireError.error) ?? .unavailable("No helper status was returned."))
                        )
                    }
                }
            }
        }
        do {
            return HelperStatus(
                availability: .enabled, setup: try JSONDecoder().decode(SystemSetupStatus.self, from: data))
        } catch {
            throw JerdError.unavailable(
                "The helper returned a status that this app cannot read. Update Jerd, then retry.")
        }
    }

    /// Registers the helper after the user approved HTTPS setup. It waits for a running automatic
    /// restart, so two registrations never race.
    public func approve() async throws {
        try await waitForRunningRestart()
        try registration.register()
    }

    /// Asks the helper for the HTTP and HTTPS listeners on ports 80 and 443.
    ///
    /// A late reply after a timeout closes the listeners it carries.
    public func acquireListeners() async throws -> LoopbackListenerPair {
        let connection = connection
        let pair: LoopbackListenerPair = try await recovering {
            try await connection.call { proxy, gate in
                proxy.acquireListeners { http, https, error in
                    guard let http, let https else {
                        let failure =
                            error.map(HelperWireError.error)
                            ?? .unavailable("The helper did not return standard-port sockets.")
                        gate.resolve(.failure(failure))
                        return
                    }
                    let pair = LoopbackListenerPair(http: http, https: https)
                    if !gate.resolve(.success(pair)) { pair.close() }
                }
            }
        }
        holdsListeners = true
        return pair
    }

    /// Returns the listeners. Without a connection there is nothing to release.
    public func releaseListeners() async {
        holdsListeners = false
        guard await connection.isConnected else { return }
        do {
            let _: Bool = try await connection.call { proxy, gate in
                proxy.releaseListeners { gate.resolve(.success(true)) }
            }
        } catch {
            // The helper releases the lease when the connection closes, so a failed release is harmless.
        }
    }

    /// Drops the connection. The next call connects again.
    /// The helper ends the lease of a closed connection, so no listeners are held afterwards.
    public func invalidate() async {
        holdsListeners = false
        await connection.invalidate()
    }

    /// Registers the helper again after the user approved a reconnection. Hosts and trust stay.
    /// The caller stopped the sites first. A running automatic restart is reused: when it succeeds,
    /// the helper was just registered again. A later stale helper may be restarted automatically again.
    public func reconnect() async throws {
        holdsListeners = false
        if try await joinRunningRestarts() { return }
        try await runRestart(finishing: .available)
    }

    /// Unregisters the helper after its setup was removed. A running restart ends first, so it
    /// cannot register the helper again after the removal. The removal itself runs like a restart
    /// that other calls wait for, so no automatic restart can start while it suspends; afterwards
    /// the daemon is not registered and no call reaches a stale helper.
    public func unregister() async throws {
        holdsListeners = false
        try await waitForRestartToEnd()
        let (connection, registration) = (connection, registration)
        try await runExclusive(finishing: automaticRestart) {
            await connection.invalidate()
            try await registration.unregister()
        }
    }

    /// Waits at most `limit` for a running restart, for Quit: a quit during the restart could
    /// leave the helper unregistered. Returns false when the limit passed; Quit then continues.
    public func finishRunningRestart(within limit: Duration) async -> Bool {
        guard case .running(_, let task) = automaticRestart else { return true }
        do {
            try await Self.wait(for: task, timeout: limit)
        } catch let error as JerdError where error == ReplyGate<Void>.timeoutError {
            return false
        } catch {
            // The restart failed or the quit was cancelled; either way it no longer runs for Quit.
        }
        return true
    }
}
