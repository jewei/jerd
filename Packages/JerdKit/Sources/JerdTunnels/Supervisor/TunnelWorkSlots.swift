import Foundation

/// The one work task of each tunnel, keyed by generation.
///
/// Work clears only its own slot: `clear(_:generation:)` does nothing when the slot holds the work
/// of another generation. Earlier builds cleared a shared slot after an `await`, so a late task
/// could erase the task of a newer Connect, and Stop could no longer cancel it (spec E 7.1.1).
package struct TunnelWorkSlots: Sendable {
    private var slots: [UUID: TunnelWork] = [:]

    package init() {}

    /// True when no tunnel has work.
    package var isEmpty: Bool { slots.isEmpty }

    /// The tunnels that have work.
    package var ids: Set<UUID> { Set(slots.keys) }

    /// The generation whose work is in the slot of `id`, or nil.
    package func generation(of id: UUID) -> TunnelGeneration? { slots[id]?.generation }

    /// Puts `work` in the slot of `id`. The supervisor stores work only in an empty slot, or over
    /// work of the same generation.
    package mutating func store(_ work: TunnelWork, for id: UUID) {
        slots[id] = work
    }

    /// Empties the slot of `id` only when it still holds the work of `generation`.
    /// - Returns: true when the slot was cleared.
    @discardableResult
    package mutating func clear(_ id: UUID, generation: TunnelGeneration) -> Bool {
        guard slots[id]?.generation == generation else { return false }
        slots[id] = nil
        return true
    }

    /// Removes the work of `id` of any generation. Only Stop uses it; Stop then cancels the work
    /// and waits for it.
    package mutating func take(_ id: UUID) -> TunnelWork? {
        slots.removeValue(forKey: id)
    }
}
