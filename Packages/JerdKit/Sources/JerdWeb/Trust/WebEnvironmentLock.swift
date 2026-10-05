import JerdFoundation

/// The messages of `environment/processes/recovery.lock`, which the engine holds while it runs.
enum WebEnvironmentLock {
    static let messages = InstanceLock.Messages(
        unavailable: "Cannot lock the web environment.",
        busy: "Another Jerd session is using this web environment.")
}
