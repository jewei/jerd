import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct PortLeaseCoordinatorTests {
    private let first = UUID()
    private let second = UUID()

    private func leased(_ resource: String = "pair") throws -> PortLeaseCoordinator<String> {
        var coordinator = PortLeaseCoordinator<String>()
        guard case .proceed = try coordinator.beginAcquire(connection: first, owner: 501) else {
            throw CancellationError()
        }
        try coordinator.finishAcquire(connection: first, owner: 501, resource: resource, connectionAlive: true)
        return coordinator
    }

    @Test func theSameConnectionGetsTheSameListenersAgain() throws {
        var coordinator = try leased()
        guard case .existing(let resource) = try coordinator.beginAcquire(connection: first, owner: 501) else {
            Issue.record("Expected the existing lease")
            return
        }
        #expect(resource == "pair" && coordinator.activity == .idle)
    }

    @Test func anotherConnectionOrOwnerIsRefused() throws {
        var coordinator = try leased()
        let message = JerdError.unavailable("Another Jerd connection owns the standard ports.")
        #expect(throws: message) { try coordinator.beginAcquire(connection: second, owner: 501) }
        #expect(throws: message) { try coordinator.beginAcquire(connection: first, owner: 502) }
    }

    @Test(arguments: PortLeaseCoordinator<String>.Mutation.allCases)
    func aLeaseBlocksEverySetupChange(mutation: PortLeaseCoordinator<String>.Mutation) throws {
        var coordinator = try leased()
        #expect(throws: JerdError.invalid("Stop Jerd's environment before \(mutation.rawValue) system setup.")) {
            try coordinator.beginMutation(mutation)
        }
        #expect(coordinator.release(connection: first) == "pair")
        try coordinator.beginMutation(mutation)
    }

    @Test func oneChangeOrAcquisitionAtATime() throws {
        var coordinator = PortLeaseCoordinator<String>()
        try coordinator.beginMutation(.configure)
        let busy = JerdError.unavailable("System setup is in progress. Retry shortly.")
        #expect(throws: busy) { try coordinator.beginMutation(.remove) }
        #expect(throws: busy) { try coordinator.beginAcquire(connection: first, owner: 501) }
        coordinator.endMutation()
        _ = try coordinator.beginAcquire(connection: first, owner: 501)
        #expect(throws: busy) { try coordinator.beginMutation(.recover) }
        #expect(throws: busy) { try coordinator.beginAcquire(connection: second, owner: 501) }
    }

    @Test func aConnectionClosedDuringAcquisitionGetsNoLease() throws {
        var coordinator = PortLeaseCoordinator<String>()
        _ = try coordinator.beginAcquire(connection: first, owner: 501)
        #expect(throws: JerdError.unavailable("The helper connection was closed.")) {
            try coordinator.finishAcquire(connection: first, owner: 501, resource: "pair", connectionAlive: false)
        }
        #expect(coordinator.lease == nil && coordinator.activity == .idle)
    }

    @Test func aFailedAcquisitionReturnsToIdle() throws {
        var coordinator = PortLeaseCoordinator<String>()
        _ = try coordinator.beginAcquire(connection: first, owner: 501)
        try coordinator.finishAcquire(connection: first, owner: 501, resource: nil, connectionAlive: true)
        #expect(coordinator.activity == .idle && coordinator.lease == nil)
    }

    @Test func releaseIgnoresOtherConnections() throws {
        var coordinator = try leased()
        #expect(coordinator.release(connection: second) == nil)
        #expect(coordinator.lease?.connection == first)
        #expect(coordinator.release(connection: first) == "pair")
        #expect(coordinator.release(connection: first) == nil)
    }
}
