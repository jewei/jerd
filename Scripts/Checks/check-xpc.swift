// Local integration harness. Does not register a service or change system files.
import Foundation
import Darwin

private final class ProbeService: NSObject, JerdHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    let sockets: ListeningSockets
    let requirement: String
    init(requirement: String) throws {
        self.requirement = requirement
        sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: JerdHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
    func status(reply: @escaping @Sendable (Data?, String?) -> Void) { reply(nil, "Not used by this test") }
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void) { reply("Not used by this test") }
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void) {
        reply(sockets.http, sockets.https, nil)
    }
    func releaseListeners(reply: @escaping @Sendable () -> Void) { sockets.close(); reply() }
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void) { reply("Not used by this test") }
    func removeSetup(reply: @escaping @Sendable (String?) -> Void) { reply("Not used by this test") }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<ListeningSockets, any Error>?
    let done = DispatchSemaphore(value: 0)
    func finish(_ result: Result<ListeningSockets, any Error>) {
        lock.withLock {
            guard value == nil else { return }
            value = result
            done.signal()
        }
    }
    func result() throws -> ListeningSockets {
        try lock.withLock { try value!.get() }
    }
}

@main
enum XPCCheck {
    static func main() throws {
        let mode = CommandLine.arguments.dropFirst().first ?? "allow"
        let team = try SystemService.currentTeamID()
        let app = try SystemService.signingRequirement(identifier: SystemService.appIdentifier, teamID: team)
        let helper = try SystemService.signingRequirement(identifier: SystemService.helperIdentifier, teamID: team)
        let listener = NSXPCListener.anonymous()
        let service = try ProbeService(requirement: mode == "reject-client" ? helper : app)
        defer { service.sockets.close() }
        listener.setConnectionCodeSigningRequirement(service.requirement)
        listener.delegate = service
        listener.resume()
        defer { listener.invalidate() }
        let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: JerdHelperProtocol.self)
        client.setCodeSigningRequirement(mode == "reject-server" ? helper : app)
        client.resume()
        defer { client.invalidate() }
        let result = ResultBox()
        let proxy = client.remoteObjectProxyWithErrorHandler { @Sendable error in result.finish(.failure(error)) } as! any JerdHelperProtocol
        proxy.acquireListeners { http, https, error in
            if let http, let https { result.finish(.success(ListeningSockets(http: http, https: https))) }
            else { result.finish(.failure(JerdError.unavailable(error ?? "No sockets received"))) }
        }
        guard result.done.wait(timeout: .now() + 10) == .success else {
            throw JerdError.unavailable("XPC did not return a result")
        }
        do {
            let received = try result.result()
            defer { received.close() }
            guard mode == "allow" else { throw JerdError.invalid("XPC accepted an incorrect code identity") }
            let expected = try service.sockets.ports()
            service.sockets.close()
            let actual = try received.ports()
            guard expected.http == actual.http, expected.https == actual.https else {
                throw JerdError.invalid("Transferred socket ports changed")
            }
            print("PASS: signed XPC transferred both loopback sockets; receiver retains them after sender close.")
        } catch {
            if mode != "allow", (error as NSError).domain == NSCocoaErrorDomain {
                print("PASS: XPC rejected the incorrect \(mode) code identity: \((error as NSError).code).")
            } else { throw error }
        }
        withExtendedLifetime(service) {}
    }
}
