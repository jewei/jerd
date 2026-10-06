import JerdProcess

/// The two loopback ports of storage: the S3 API and the RustFS console.
public struct StoragePorts: Equatable, Hashable, Sendable {
    public var api: UInt16
    public var console: UInt16

    public init(api: UInt16, console: UInt16) {
        self.api = api
        self.console = console
    }

    /// Both ports are 1024 or above and they differ.
    public var isValid: Bool {
        api >= LoopbackPortGuard.minimumPort && console >= LoopbackPortGuard.minimumPort && api != console
    }

    /// The ports in the order that a start checks them.
    public var ordered: [UInt16] { [api, console] }
}
