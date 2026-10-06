import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct HelperRegistrationTests {
    private func registration(_ service: FakeDaemonService, signed: Bool = true) -> HelperRegistration {
        HelperRegistration(service: service) {
            if !signed { throw JerdError.unavailable("unsigned") }
        }
    }

    @Test(arguments: [HelperAvailability.notRegistered, .notFound])
    func registersAnUnregisteredDaemon(status: HelperAvailability) throws {
        let service = FakeDaemonService(status)
        try registration(service).register()
        #expect(service.calls == ["register"] && service.status == .enabled)
    }

    @Test func anEnabledDaemonIsNotRegisteredAgain() throws {
        let service = FakeDaemonService(.enabled)
        try registration(service).register()
        #expect(service.calls.isEmpty)
    }

    @Test func aDaemonWaitingForApprovalAsksTheUser() {
        let service = FakeDaemonService(.notRegistered, afterRegister: .requiresApproval)
        #expect(
            throws: JerdError.unavailable(
                "Allow Jerd in System Settings → General → Login Items & Extensions, then retry the operation.")
        ) {
            try registration(service).register()
        }
        let waiting = FakeDaemonService(.requiresApproval)
        #expect(throws: JerdError.self) { try registration(waiting).register() }
        #expect(waiting.calls.isEmpty)
    }

    @Test func aDaemonThatStaysUnregisteredReportsTheRegisterError() {
        let service = FakeDaemonService(.notFound, afterRegister: .notFound)
        #expect(throws: JerdError.unavailable("Launch denied by user")) { try registration(service).register() }
    }

    @Test func anUnsignedBuildCannotRegister() {
        let service = FakeDaemonService(.notRegistered)
        #expect(throws: JerdError.unavailable("unsigned")) { try registration(service, signed: false).register() }
        #expect(service.calls.isEmpty)
    }

    @Test(arguments: [HelperAvailability.enabled, .requiresApproval])
    func reregisterUnregistersFirst(status: HelperAvailability) async throws {
        let service = FakeDaemonService(status)
        try await registration(service).reregister()
        #expect(service.calls == ["unregister", "register"] && service.status == .enabled)
    }

    @Test func reregisterOfAnUnregisteredDaemonOnlyRegisters() async throws {
        let service = FakeDaemonService(.notRegistered)
        try await registration(service).reregister()
        #expect(service.calls == ["register"])
    }
}
