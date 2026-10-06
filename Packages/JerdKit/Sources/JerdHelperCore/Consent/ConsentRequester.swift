import Foundation
import JerdFoundation
import JerdSystem

/// The helper side of the reverse call, over the same authenticated connection as the request.
///
/// There is no timeout: the user can take as long as needed at the macOS prompt. A closed
/// connection, a transport error, or a missing interface ends the wait with `.approvalInterrupted`.
/// The first result wins; later ones are ignored.
struct ConsentRequester: ConsentRequesting {
    /// Gives the reverse interface of the session, or the reason why it is missing.
    let channel: @Sendable (_ onError: @escaping @Sendable (any Error) -> Void) -> ConsentChannel

    func change(_ request: TrustConsentRequest) async throws -> Int32 {
        let data = try HelperWireProtocol.encode(request)
        return try await ReplyGate<Int32>.wait(cancellation: .awaitReply, timeout: nil) { gate in
            let remote = channel { error in
                gate.resolve(
                    .failure(
                        JerdError.approvalInterrupted(
                            "The app connection closed during certificate approval: \(error.localizedDescription)")))
            }
            switch remote {
            case .closed:
                gate.resolve(
                    .failure(JerdError.approvalInterrupted("The app connection closed before certificate approval.")))
            case .unavailable:
                gate.resolve(
                    .failure(JerdError.approvalInterrupted("The certificate consent interface is unavailable.")))
            case .open(let consent):
                consent.changeTrust(data) { status in gate.resolve(.success(status)) }
            }
        }
    }

    /// A requester over `connection`. The connection is held weakly, so a closed session ends approvals.
    static func over(_ connection: NSXPCConnection) -> ConsentRequester {
        let reference = WeakConnection(connection)
        return ConsentRequester { onError in
            guard let connection = reference.connection else { return .closed }
            guard let consent = connection.remoteObjectProxyWithErrorHandler(onError) as? any JerdTrustConsentProtocol
            else { return .unavailable }
            return .open(consent)
        }
    }
}
