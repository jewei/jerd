/// Identifies one Connect request of one tunnel. Work and results of an older generation never
/// change the state of a newer one.
package struct TunnelGeneration: Hashable, Sendable, CustomStringConvertible {
    package let value: UInt64

    package init(_ value: UInt64) { self.value = value }

    package var description: String { "generation \(value)" }
}
