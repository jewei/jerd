import Foundation
import JerdFoundation
import JerdSystem
import Security
import Testing
import os

@testable import JerdHelperCore

/// A copy of the old app's view of the helper protocol, under another runtime name.
@objc(OldAppHelperProtocol) protocol OldAppHelperProtocol {
    func status(reply: @escaping @Sendable (Data?, String?) -> Void)
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void)
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void)
    func releaseListeners(reply: @escaping @Sendable () -> Void)
    func removeSetup(reply: @escaping @Sendable (String?) -> Void)
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void)
}

@objc(OldAppConsentProtocol) protocol OldAppConsentProtocol {
    func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void)
}

final class OldAppConsent: NSObject, OldAppConsentProtocol, Sendable {
    func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void) { reply(0) }
}

/// Real XPC in this process: an old app against the new listener delegate and session.
/// The runner's own designated requirement accepts it, and a Jerd requirement refuses it.
@Suite struct HelperXPCInteropTests {
    private func ownRequirement() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
            SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text
        else { throw JerdError.unavailable("The test runner has no designated requirement.") }
        return text as String
    }

    private func connect(_ listener: NSXPCListener) -> NSXPCConnection {
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: (any OldAppHelperProtocol).self)
        connection.exportedInterface = NSXPCInterface(with: (any OldAppConsentProtocol).self)
        connection.exportedObject = OldAppConsent()
        connection.resume()
        return connection
    }

    private func status(_ connection: NSXPCConnection) async -> (Data?, String?) {
        await withCheckedContinuation { continuation in
            let gate = ReplyGateBox(continuation)
            let proxy =
                connection.remoteObjectProxyWithErrorHandler { gate.finish((nil, "\($0)")) }
                as? any OldAppHelperProtocol
            proxy?.status { gate.finish(($0, $1)) }
        }
    }

    @Test func anOldAppConfiguresAndReadsTheNewHelper() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let delegate = HelperListenerDelegate(requirement: try ownRequirement(), service: harness.service)
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let connection = connect(listener)
        defer { connection.invalidate() }
        let payload = try harness.request()
        let error: String? = await withCheckedContinuation { continuation in
            let gate = ReplyGateBox(continuation)
            let proxy =
                connection.remoteObjectProxyWithErrorHandler { gate.finish("\($0)") } as? any OldAppHelperProtocol
            proxy?.configureSite(payload) { gate.finish($0) }
        }
        #expect(error == nil)
        let (data, statusError) = await status(connection)
        #expect(statusError == nil)
        let decoded = try JSONDecoder().decode(SystemSetupStatus.self, from: #require(data))
        #expect(decoded.hostnames == ["demo.test"] && decoded.hostsConfigured)
        withExtendedLifetime(delegate) {}
    }

    @Test func aPeerWithoutTheRequiredSignatureIsRefused() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let requirement = try CodeSigningPolicy.requirement(identifier: "dev.jerd.app", teamID: "ABCDE12345")
        let delegate = HelperListenerDelegate(requirement: requirement, service: harness.service)
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let connection = connect(listener)
        defer { connection.invalidate() }
        let (data, error) = await status(connection)
        #expect(data == nil && error != nil)
        withExtendedLifetime(delegate) {}
    }
}

/// Resumes a continuation once, from any of several callbacks.
private final class ReplyGateBox<Value: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func finish(_ value: Value) {
        let current = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        current?.resume(returning: value)
    }
}
