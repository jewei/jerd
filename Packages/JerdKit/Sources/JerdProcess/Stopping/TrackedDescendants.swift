import Darwin
import os

/// The descendants of one supervised leader that a parent-chain walk found, kept for the life of
/// the child, so that a process that left the group still blocks `.stopped` after its parent exited.
final class TrackedDescendants: Sendable {
    private let members = OSAllocatedUnfairLock<[ProcessTree.Member]>(initialState: [])

    /// Adds the members that are not tracked yet.
    func track(_ found: [ProcessTree.Member]) {
        members.withLock { tracked in
            for member in found where !tracked.contains(where: { $0.isSameProcess(as: member) }) {
                tracked.append(member)
            }
        }
    }

    /// Every tracked member, in the order found.
    var all: [ProcessTree.Member] { members.withLock { $0 } }

    /// Forgets the members that `tree` proves gone. Returns the rest with their current state.
    func refresh(using tree: ProcessTree) -> [ProcessTree.Lookup] {
        let states = all.map { ($0, tree.current($0)) }
        let gone = states.filter { $0.1 == .gone }.map(\.0)
        members.withLock { tracked in
            tracked.removeAll { member in gone.contains { $0.isSameProcess(as: member) } }
        }
        return states.map(\.1).filter { $0 != .gone }
    }
}
