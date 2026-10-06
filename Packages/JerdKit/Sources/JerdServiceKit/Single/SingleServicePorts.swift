/// The loopback ports of a single-instance service.
package protocol SingleServicePorts: Equatable, Sendable {
    /// Every port, in the order that a start checks them.
    var ordered: [UInt16] { get }
}
