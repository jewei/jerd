import JerdSystem

/// Binds the standard-port listeners. Tests bind ephemeral ports instead of 80 and 443.
protocol ListenerBinding: Sendable {
    func bindStandardPorts() throws -> LoopbackListenerPair
}
