import Darwin
import JerdProcess
import Testing

@Suite struct RecoveryClassifierTests {
    private let identity = IdentityFactory.make(pid: 4_242)
    private let child = IdentityFactory.make(pid: 4_243)

    private func record(
        identity: ProcessIdentity?, controller: Bool = true, descendants: [ProcessIdentity]? = nil
    )
        -> ActiveRunRecord
    {
        ActiveRunRecord(
            processID: 4_242, runtimeID: "rt", identity: identity,
            controller: controller ? IdentityFactory.make(pid: 77) : nil, gracefulSignal: SIGTERM,
            descendants: descendants)
    }

    private func observe(
        master: ProcessIdentity.Match? = .running, controller: ProcessIdentity.Match? = .exited,
        descendants: [ProcessIdentity.Match] = [], legacyGone: Bool = false,
        group: ProcessGroupInspector.Membership = .members([4_242]), user: uid_t = geteuid(), supported: Bool = true
    ) -> ProcessObservation {
        ProcessObservation(
            master: master, controller: controller, descendants: descendants, legacyLeaderGone: legacyGone,
            group: group,
            currentUserID: user, auditedSignalsSupported: supported)
    }

    @Test func staleRulesForRecordsWithAnIdentity() {
        let full = record(identity: identity)
        let withChild = record(identity: identity, descendants: [child])
        #expect(RecoveryClassifier.isStale(full, observe(master: .exited, group: .empty)))
        #expect(!RecoveryClassifier.isStale(full, observe(master: .exited, group: .members([4_300]))))
        #expect(!RecoveryClassifier.isStale(full, observe(master: .exited, group: .unknown)))
        #expect(RecoveryClassifier.isStale(full, observe(master: .replaced, group: .members([4_300]))))
        #expect(!RecoveryClassifier.isStale(full, observe(master: .running, group: .empty)))
        #expect(!RecoveryClassifier.isStale(full, observe(master: .unknown, group: .empty)))
        #expect(!RecoveryClassifier.isStale(withChild, observe(master: .replaced, descendants: [.running])))
        #expect(
            RecoveryClassifier.isStale(withChild, observe(master: .exited, descendants: [.replaced], group: .empty)))
    }

    @Test func staleRulesForRecordsWithoutAnIdentity() {
        let legacy = record(identity: nil, controller: false)
        #expect(RecoveryClassifier.isStale(legacy, observe(master: nil, legacyGone: true, group: .empty)))
        #expect(!RecoveryClassifier.isStale(legacy, observe(master: nil, legacyGone: true, group: .unknown)))
        #expect(!RecoveryClassifier.isStale(legacy, observe(master: nil, legacyGone: false, group: .empty)))
    }

    @Test func groupMembersAreVerifiedOnlyByRunningRecordedIdentities() {
        let withChild = record(identity: identity, descendants: [child])
        #expect(!RecoveryClassifier.hasUnverifiedGroupMembers(withChild, observe(master: .replaced, group: .unknown)))
        #expect(RecoveryClassifier.hasUnverifiedGroupMembers(withChild, observe(group: .unknown)))
        #expect(
            !RecoveryClassifier.hasUnverifiedGroupMembers(
                withChild, observe(descendants: [.running], group: .members([4_242, 4_243]))))
        #expect(
            RecoveryClassifier.hasUnverifiedGroupMembers(
                withChild, observe(descendants: [.exited], group: .members([4_242, 4_243]))))
        #expect(
            RecoveryClassifier.hasUnverifiedGroupMembers(
                withChild, observe(descendants: [.running], group: .members([4_242, 4_999]))))
        #expect(!RecoveryClassifier.hasUnverifiedGroupMembers(withChild, observe(master: .exited, group: .empty)))
    }

    @Test func classificationStatesAndDetails() {
        let full = record(identity: identity)
        let table: [(ActiveRunRecord, ProcessObservation, RecoveryFinding.State, String)] = [
            (
                full, observe(master: .exited, group: .empty), .stale,
                "The saved process has exited or its PID was reused. Clear this stale record to retry Start."
            ),
            (
                record(identity: nil, controller: true), observe(master: nil), .manual,
                "Legacy process record for PID 4242. Ownership cannot be proved. Inspect its executable and stop the "
                    + "service manually; Jerd will not signal this PID."
            ),
            (
                record(identity: identity, controller: false), observe(controller: nil), .manual,
                "Legacy process record for PID 4242. Ownership cannot be proved. Inspect its executable and stop the "
                    + "service manually; Jerd will not signal this PID."
            ),
            (
                full, observe(controller: .running), .managed,
                "A running Jerd session manages PID 4242. Use its normal Stop control."
            ),
            (
                full, observe(controller: .replaced), .recoverable,
                "rt · PID 4242\n/bin/x\nThe previous Jerd session ended. Request a graceful stop, then retry Start."
            ),
        ]
        for (record, observation, state, detail) in table {
            let verdict = RecoveryClassifier.classify(record, observation)
            #expect(verdict.state == state)
            #expect(verdict.detail == detail)
        }
    }

    @Test func everyRecoverableConditionIsRequired() {
        let uncertain =
            "Ownership of PID 4242 is uncertain. The record and data were preserved. Inspect this service manually."
        let full = record(identity: identity)
        let withChild = record(identity: identity, descendants: [child])
        let failing: [(ActiveRunRecord, ProcessObservation)] = [
            (full, observe(controller: .unknown)),
            (full, observe(user: geteuid() + 1)),
            (full, observe(supported: false)),
            (record(identity: IdentityFactory.make(pid: 4_242, audit: nil)), observe()),
            (full, observe(master: .unknown)),
            (withChild, observe(descendants: [.unknown])),
            (full, observe(master: .exited, group: .members([4_300]))),
            (full, observe(master: .exited, group: .unknown)),
        ]
        for (record, observation) in failing {
            #expect(RecoveryClassifier.classify(record, observation) == .init(state: .manual, detail: uncertain))
        }
        #expect(
            RecoveryClassifier.classify(
                withChild, observe(master: .exited, descendants: [.running], group: .members([4_243]))
            )
            .state == .recoverable)
    }
}
