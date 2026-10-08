import Foundation
import JerdFoundation
import ServiceManagement
import Testing
import os

@testable import JerdSystem

@Suite struct HelperRegistrationTests {
    private func registration(_ service: FakeDaemonService, signed: Bool = true) -> HelperRegistration {
        HelperRegistration(service: service, processes: service) {
            if !signed { throw JerdError.unavailable("unsigned") }
        } pause: { _ in
        }
    }

    private static let loginItems = JerdError.unavailable(
        "Allow Jerd in System Settings → General → Login Items & Extensions, then retry the operation."
    ).with(.openLoginItems)

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

    @Test func aDaemonWaitingForApprovalAsksTheUserAndOffersLoginItems() {
        let service = FakeDaemonService(.notRegistered, afterRegister: .requiresApproval)
        #expect(throws: Self.loginItems) { try registration(service).register() }
        let waiting = FakeDaemonService(.requiresApproval)
        #expect(throws: Self.loginItems) { try registration(waiting).register() }
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

    /// Regression test of the field failure: `unregister()` returned while the old helper still
    /// exited, `register()` failed with "Operation not permitted", and the login item stayed off.
    @Test func reregisterWaitsUntilTheOldHelperExitedBeforeItRegisters() async throws {
        let service = FakeDaemonService(.enabled)
        service.configure {
            $0.exitingChecks = 3
            $0.refusesWhileExiting = true
        }
        let pauses = OSAllocatedUnfairLock(initialState: [Duration]())
        try await service.registration(pauses: pauses).reregister()
        #expect(service.calls == ["unregister", "register"] && service.status == .enabled)
        #expect(pauses.withLock { $0 } == Array(repeating: HelperRegistration.exitPollInterval, count: 3))
    }

    @Test func aTransientRegisterFailureIsRetriedABoundedNumberOfTimes() async throws {
        let service = FakeDaemonService(.enabled)
        let refused = FakeDaemonService.operationNotPermitted
        service.configure { $0.registerErrors = [refused, refused] }
        let pauses = OSAllocatedUnfairLock(initialState: [Duration]())
        try await service.registration(pauses: pauses).reregister()
        #expect(service.calls == ["unregister", "register", "register", "register"])
        #expect(
            pauses.withLock { $0 } == [HelperRegistration.registerRetryDelay, HelperRegistration.registerRetryDelay])

        let stuck = FakeDaemonService(.enabled)
        stuck.configure { $0.registerErrors = Array(repeating: refused, count: 10) }
        await #expect(throws: HelperRegistrationFailure.disabledError) {
            try await stuck.registration().reregister()
        }
        #expect(stuck.calls.filter { $0 == "register" }.count == HelperRegistration.registerAttempts)
    }

    @Test func anOldHelperThatNeverExitsStopsWaitingAtTheTimeLimit() async throws {
        let service = FakeDaemonService(.enabled)
        service.configure { $0.exitingChecks = 1_000 }
        let pauses = OSAllocatedUnfairLock(initialState: [Duration]())
        try await service.registration(pauses: pauses).reregister()
        let waited = pauses.withLock { $0 }.reduce(Duration.zero, +)
        #expect(waited == HelperRegistration.exitTimeLimit)
        #expect(service.status == .enabled)
    }

    @Test func aDaemonThatIsAlreadyGoneNeedsNoUnregistration() async throws {
        let service = FakeDaemonService(.enabled)
        service.configure {
            $0.unregisterError = NSError(
                domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorJobNotFound))
        }
        try await registration(service).reregister()
        #expect(service.status == .enabled)
    }

    @Test func aRawUnregisterFailureBecomesAnActionableMessage() async {
        let service = FakeDaemonService(.enabled)
        service.configure { $0.unregisterError = NSError(domain: NSCocoaErrorDomain, code: 4_099) }
        await #expect(throws: HelperRegistrationFailure.error(for: NSError(domain: NSCocoaErrorDomain, code: 4_099))) {
            try await registration(service).reregister()
        }
    }

    @Test(arguments: [
        (NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)), HelperRegistrationFailure.transient),
        (NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(EPERM)), .transient),
        (NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorLaunchDeniedByUser)), .disabled),
        (NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorJobMustBeEnabled)), .disabled),
        (
            NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorInvalidSignature)),
            .invalidSignature
        ),
        (
            NSError(domain: HelperRegistrationFailure.frameworkDomain, code: Int(kSMErrorToolNotValid)),
            .invalidSignature
        ),
        (NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorJobPlistNotFound)), .missingHelper),
        (NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorJobNotFound)), .notRegistered),
        (
            NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorInternalFailure)),
            .other(domain: HelperRegistrationFailure.serviceDomain, code: 2)
        ),
        (NSError(domain: NSCocoaErrorDomain, code: 4_099), .other(domain: NSCocoaErrorDomain, code: 4_099)),
    ])
    func everyRegistrationFailureHasACause(error: NSError, cause: HelperRegistrationFailure) {
        #expect(HelperRegistrationFailure.classify(error) == cause)
    }

    @Test func noRegistrationFailureShowsARawCocoaText() {
        let errors = [
            NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
            NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorLaunchDeniedByUser)),
            NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorInvalidSignature)),
            NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorJobPlistNotFound)),
            NSError(domain: HelperRegistrationFailure.serviceDomain, code: Int(kSMErrorJobNotFound)),
            NSError(domain: NSCocoaErrorDomain, code: 4_099),
        ]
        for error in errors {
            let shown = HelperRegistrationFailure.error(for: error)
            #expect(!shown.message.contains(error.localizedDescription))
            #expect(!shown.message.contains("Operation not permitted"))
            #expect(shown.message.hasSuffix(".") || shown.message.hasSuffix(")"))
        }
        #expect(HelperRegistrationFailure.error(for: errors[0]).remedy == .openLoginItems)
        #expect(HelperRegistrationFailure.error(for: errors[1]).remedy == .openLoginItems)
        #expect(HelperRegistrationFailure.error(for: errors[5]).remedy == .reconnectHelper)
        #expect(HelperRegistrationFailure.error(for: JerdError.invalid("Kept.")) == JerdError.invalid("Kept."))
    }

    @Test func theProcessTableFindsRootProcessesByName() {
        #expect(HelperProcessTable.commandName == "JerdHelper")
        #expect(HelperProcessTable.isHelper(1, named: "launchd"))
        #expect(!HelperProcessTable.isHelper(getpid(), named: HelperProcessTable.commandName))
        #expect(!HelperProcessTable.processIDs().isEmpty)
    }
}
