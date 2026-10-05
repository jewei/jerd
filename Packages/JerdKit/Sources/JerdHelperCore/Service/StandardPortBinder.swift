import JerdSystem

/// Binds `127.0.0.1:80` and `127.0.0.1:443`.
struct StandardPortBinder: ListenerBinding {
    func bindStandardPorts() throws -> LoopbackListenerPair {
        try LoopbackListenerPair.bind(
            httpPort: LoopbackListenerPair.standardPorts.http, httpsPort: LoopbackListenerPair.standardPorts.https)
    }
}
