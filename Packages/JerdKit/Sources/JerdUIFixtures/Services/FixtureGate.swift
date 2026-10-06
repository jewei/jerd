/// Holds an in-memory registry change until a test opens it. It ignores task cancellation on
/// purpose: a live manager can finish its work after the user cancelled the wait.
public actor FixtureGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// True while a call waits at the gate.
    public var isHolding: Bool { !waiters.isEmpty }

    /// Waits until `open()`, or returns at once when the gate is open.
    public func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Lets every waiting and later call through.
    public func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
