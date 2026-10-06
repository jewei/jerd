import Foundation
import os

/// The per-launch state of storage: the S3 session of the current RustFS launch and the bucket
/// names that it listed.
///
/// A launch begins in `RustFSDefinition.prepareStart` and ends in its `LaunchPlan.didStop`, which
/// the kit runs after every kind of stop (Stop, an exit, a reap outside Jerd) and after a launch
/// that failed. The end releases the session and forgets the names, so a new launch never shows
/// the names of an earlier one, and a late answer of an ended launch never changes a newer one.
final class StorageLaunch: Sendable {
    /// The current launch, as bucket operations use it.
    struct Handle: Sendable {
        let id: UUID
        let sender: any S3Sending
    }

    private struct Current: Sendable {
        let id: UUID
        let session: S3Session
        var names: Set<String> = []
    }

    private let state = OSAllocatedUnfairLock<Current?>(initialState: nil)

    /// Begins a launch with `session` and returns its ID. An earlier launch that did not end is
    /// ended first.
    func begin(_ session: S3Session) -> UUID {
        let id = UUID()
        let earlier = state.withLock { current -> S3Session? in
            let earlier = current?.session
            current = Current(id: id, session: session)
            return earlier
        }
        earlier?.end()
        return id
    }

    /// Ends the launch `id`: releases its session and forgets its names. A newer launch stays.
    func end(_ id: UUID) {
        let ended = state.withLock { current -> S3Session? in
            guard let launch = current, launch.id == id else { return nil }
            current = nil
            return launch.session
        }
        ended?.end()
    }

    /// The current launch, or nil when no launch is current.
    var current: Handle? {
        state.withLock { current in current.map { Handle(id: $0.id, sender: $0.session.sender) } }
    }

    /// The names that the current launch listed. Empty without a launch.
    var names: Set<String> { state.withLock { $0?.names ?? [] } }

    /// Replaces the names of launch `id`. An ended launch changes nothing.
    func replaceNames(_ names: Set<String>, of id: UUID) {
        state.withLock { current in
            guard current?.id == id else { return }
            current?.names = names
        }
    }

    /// Adds `name` to the names of launch `id`. An ended launch changes nothing.
    func insert(_ name: String, of id: UUID) {
        state.withLock { current in
            guard current?.id == id else { return }
            current?.names.insert(name)
        }
    }
}
