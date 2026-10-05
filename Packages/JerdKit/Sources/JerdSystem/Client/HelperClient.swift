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
        let availability = registration.availability
        guard availability == .enabled else { return HelperStatus(availability: availability, setup: .empty) }
        let data: Data = try await connection.call(cancellation: .readOnly) { proxy, gate in
            proxy.status { data, error in
                if let data {
                    gate.resolve(.success(data))
                } else {
                    gate.resolve(
                        .failure(error.map(HelperWireError.error) ?? .unavailable("No helper status was returned.")))
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

    /// Registers the helper after the user approved HTTPS setup.
    public func approve() throws { try registration.register() }

    /// Asks the helper for the HTTP and HTTPS listeners on ports 80 and 443.
    ///
    /// A late reply after a timeout closes the listeners it carries (fixed problem 9).
    public func acquireListeners() async throws -> LoopbackListenerPair {
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

    /// Returns the listeners. Without a connection there is nothing to release.
    public func releaseListeners() async {
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
    public func invalidate() async { await connection.invalidate() }

    /// Registers the helper again after the user approved a reconnection. Hosts and trust stay.
    public func reconnect() async throws {
        await connection.invalidate()
        try await registration.reregister()
    }

    /// Unregisters the helper after its setup was removed.
    public func unregister() async throws {
        await connection.invalidate()
        try await registration.unregister()
    }
}
