/// Tells whether a helper process still runs. After `SMAppService.unregister()` the old helper can
/// still be exiting, and a `register()` in that moment fails with "Operation not permitted".
/// `HelperProcessTable` is the live type; tests use a fake.
public protocol HelperProcessInspecting: Sendable {
    /// True while a root process of the helper executable runs.
    func isHelperRunning() -> Bool
}
