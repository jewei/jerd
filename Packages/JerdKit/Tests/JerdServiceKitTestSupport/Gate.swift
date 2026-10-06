/// Holds waiting tasks until `open()`. Later waits pass at once.
package actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    package init() {}

    /// The number of tasks that wait now.
    package var waiters: Int { waiting.count }

    package func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    package func open() {
        isOpen = true
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume() }
    }
}
