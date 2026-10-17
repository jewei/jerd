import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct LoopbackPortGuardTests {
    private let free = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })

    private func guarded(_ answers: [[String]: CommandResult], probe: LoopbackProbe? = nil) -> LoopbackPortGuard {
        LoopbackPortGuard(commands: RecordingCommandRunner(answers), probe: probe ?? free)
    }

    @Test func privilegedPortsAreRefusedBeforeAnyInspection() async {
        let commands = RecordingCommandRunner([:])
        let guardian = LoopbackPortGuard(commands: commands, probe: free)
        await #expect(throws: JerdError.invalid("Use a port from 1024 to 65535.")) {
            try await guardian.requireFree(1_023)
        }
        await #expect(throws: JerdError.invalid("Use an unprivileged service port.")) {
            try await guardian.suggest(startingAt: 80)
        }
        #expect(commands.arguments.isEmpty)
    }

    @Test func anyListenerIncludingAWildcardOneMakesThePortOccupied() async {
        let occupied = JerdError.unavailable("Local port 3306 is occupied. No process was stopped.")
        let wildcard = guarded([LsofQuery.listeners(on: 3_306): CommandResult(status: 0, output: "p999\n")])
        await #expect(throws: occupied) { try await wildcard.requireFree(3_306) }
        let hidden = guarded([:], probe: LoopbackProbe(isAccepting: { _ in true }, requireBindable: { _ in }))
        await #expect(throws: occupied) { try await hidden.requireFree(3_306) }
    }

    @Test func theListenerCheckForAnyPortUsesOnlyLsof() async throws {
        let accepting = LoopbackProbe(
            isAccepting: { _ in true }, requireBindable: { _ in throw JerdError.invalid("No.") })
        try await guarded([:], probe: accepting).requireNoListener(443)
        let listed = guarded([LsofQuery.listeners(on: 443): CommandResult(status: 0, output: "p88\n")])
        await #expect(throws: JerdError.unavailable("Local port 443 is occupied. No process was stopped.")) {
            try await listed.requireNoListener(443)
        }
    }

    @Test func aFailedInspectionIsNotTreatedAsFree() async {
        let broken = guarded([LsofQuery.listeners(on: 3_306): CommandResult(status: 2, output: "lsof: error")])
        await #expect(throws: JerdError.unavailable("Cannot inspect local port 3306. No process was stopped.")) {
            try await broken.requireFree(3_306)
        }
    }

    @Test func theBindCheckRunsLastAndItsErrorIsKept() async {
        let bindError = JerdError.unavailable(
            "Loopback port 3306 is occupied or cannot be bound. No process was stopped.")
        let guardian = guarded(
            [:], probe: LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in throw bindError }))
        await #expect(throws: bindError) { try await guardian.requireFree(3_306) }
    }

    @Test func suggestionsSkipReservedAndOccupiedPorts() async throws {
        let guardian = guarded([LsofQuery.listeners(on: 1_026): CommandResult(status: 0, output: "p1\n")])
        #expect(try await guardian.suggest(startingAt: 1_025, excluding: [1_025]) == 1_027)
        let full = guarded([:], probe: LoopbackProbe(isAccepting: { _ in true }, requireBindable: { _ in }))
        await #expect(throws: JerdError.unavailable("No free service port was found. Enter a different port.")) {
            try await full.suggest(startingAt: 65_500)
        }
    }

    /// A credentialed probe may run only while the owned process alone listens on each port.
    @Test func onlyListenerRequiresTheOwnedLoopbackListenerAndNoOtherProcess() async throws {
        let pid: pid_t = 4_242
        let own = CommandResult(status: 0, output: "p4242\nf5\nn127.0.0.1:5432\nf6\nn127.0.0.1:9187\n")
        let mine = CommandResult(status: 0, output: "p4242\n")
        #expect(
            try await guarded([LsofQuery.tcp(of: pid): own, LsofQuery.listeners(on: 5_432): mine])
                .isOnlyListener(pid: pid, on: [5_432]))
        let shared = CommandResult(status: 0, output: "p4242\np777\n")
        #expect(
            try await !guarded([LsofQuery.tcp(of: pid): own, LsofQuery.listeners(on: 5_432): shared])
                .isOnlyListener(pid: pid, on: [5_432]))
        let elsewhere = CommandResult(status: 0, output: "p4242\nf5\nn*:5432\n")
        #expect(
            try await !guarded([LsofQuery.tcp(of: pid): elsewhere, LsofQuery.listeners(on: 5_432): mine])
                .isOnlyListener(pid: pid, on: [5_432]))
        #expect(
            try await !guarded([LsofQuery.tcp(of: pid): CommandResult(status: 1, output: "")])
                .isOnlyListener(pid: pid, on: [5_432]))
        #expect(try await guarded([:]).isOnlyListener(pid: pid, on: []))
    }

    @Test func onlyListenerDoesNotTreatAFailedPortInspectionAsSafe() async {
        let pid: pid_t = 4_242
        let own = CommandResult(status: 0, output: "p4242\nf5\nn127.0.0.1:5432\n")
        let broken = CommandResult(status: 2, output: "lsof: error")
        await #expect(throws: JerdError.unavailable("Cannot inspect local port 5432. No process was stopped.")) {
            _ = try await guarded([LsofQuery.tcp(of: pid): own, LsofQuery.listeners(on: 5_432): broken])
                .isOnlyListener(pid: pid, on: [5_432])
        }
    }

    @Test func ownershipRequiresExactlyTheExpectedLoopbackListeners() async throws {
        let pid: pid_t = 4_242
        let exact = CommandResult(status: 0, output: "p4242\nf5\nn127.0.0.1:3306\n")
        let mine = CommandResult(status: 0, output: "p4242\n")
        try await guarded([LsofQuery.tcp(of: pid): exact, LsofQuery.listeners(on: 3_306): mine])
            .verifyOwnership(pid: pid, expected: [3_306])
        let unexpected = JerdError.processFailed(
            "The service opened an unexpected network listener. Expected loopback only.")
        let wildcard = CommandResult(status: 0, output: "p4242\nf5\nn127.0.0.1:3306\nf6\nn*:33060\n")
        await #expect(throws: unexpected) {
            try await guarded([LsofQuery.tcp(of: pid): wildcard]).verifyOwnership(pid: pid, expected: [3_306])
        }
        await #expect(throws: unexpected) { try await guarded([:]).verifyOwnership(pid: pid, expected: [3_306]) }
    }

    @Test func udpSocketsAndSharedPortsAreRefused() async throws {
        let pid: pid_t = 4_242
        let exact = CommandResult(status: 0, output: "p4242\nf5\nn127.0.0.1:3306\n")
        let udp = CommandResult(status: 0, output: "p4242\nf9\nn127.0.0.1:5353\n")
        await #expect(throws: JerdError.processFailed("The service opened an unexpected UDP socket.")) {
            try await guarded([LsofQuery.tcp(of: pid): exact, LsofQuery.udp(of: pid): udp]).verifyOwnership(
                pid: pid, expected: [3_306])
        }
        let shared = CommandResult(status: 0, output: "p4242\np5000\n")
        await #expect(
            throws: JerdError.processFailed("Another process also uses port 3306. Each service needs its own port.")
        ) {
            try await guarded([LsofQuery.tcp(of: pid): exact, LsofQuery.listeners(on: 3_306): shared])
                .verifyOwnership(pid: pid, expected: [3_306])
        }
        try await guarded([LsofQuery.tcp(of: pid): exact, LsofQuery.udp(of: pid): udp])
            .verifyOwnership(pid: pid, expected: [3_306], requireExclusive: false, allowUDP: true)
    }

    @Test func aProcessWithoutExpectedPortsMayHaveNoListener() async throws {
        try await guarded([:]).verifyOwnership(pid: 4_242, expected: [], requireExclusive: true, allowUDP: true)
    }
}
