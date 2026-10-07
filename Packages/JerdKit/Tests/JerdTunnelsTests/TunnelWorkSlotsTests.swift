import Foundation
import JerdTunnels
import Testing

@Suite struct TunnelWorkSlotsTests {
    private let id = UUID()

    private func work(_ generation: UInt64) -> TunnelWork {
        TunnelWork(generation: TunnelGeneration(generation), task: Task {})
    }

    /// Regression test: a late launch cleared the slot of a newer Connect, so Stop could no
    /// longer cancel the newer work.
    @Test func aLateClearOfAnOlderGenerationKeepsTheWorkOfANewerConnect() {
        var slots = TunnelWorkSlots()
        slots.store(work(1), for: id)
        let stopped = slots.take(id)
        slots.store(work(2), for: id)
        let lateClear = slots.clear(id, generation: TunnelGeneration(1))
        #expect(stopped?.generation == TunnelGeneration(1))
        #expect(!lateClear)
        #expect(slots.generation(of: id) == TunnelGeneration(2))
        let newer = slots.take(id)
        #expect(newer?.generation == TunnelGeneration(2))
    }

    @Test func workClearsOnlyItsOwnSlot() {
        var slots = TunnelWorkSlots()
        let other = UUID()
        slots.store(work(1), for: id)
        slots.store(work(2), for: other)
        #expect(slots.ids == [id, other])
        let own = slots.clear(id, generation: TunnelGeneration(1))
        #expect(own)
        #expect(slots.generation(of: id) == nil)
        #expect(slots.ids == [other])
        let wrongGeneration = slots.clear(other, generation: TunnelGeneration(1))
        let rightGeneration = slots.clear(other, generation: TunnelGeneration(2))
        #expect(!wrongGeneration)
        #expect(rightGeneration)
        #expect(slots.isEmpty)
        let missing = slots.take(id)
        #expect(missing == nil)
    }
}
