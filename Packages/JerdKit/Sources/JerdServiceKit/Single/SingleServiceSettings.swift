/// The saved settings of a single-instance service: at most one runtime and its ports.
package protocol SingleServiceSettings: Equatable, Sendable {
    associatedtype Runtime: SingleServiceRuntime
    associatedtype Ports: SingleServicePorts

    /// The registered runtime. Nil until the first runtime is installed.
    var runtime: Runtime? { get set }
    var ports: Ports { get set }

    /// The structural rules of every load and save.
    func validate() throws
}
