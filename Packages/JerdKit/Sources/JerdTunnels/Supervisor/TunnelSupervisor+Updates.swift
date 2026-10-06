import Foundation

extension TunnelSupervisor {
    /// The snapshots now, and again after each change of a state, an owned connector, or the
    /// settings. A slow reader gets only the newest value. The app can read this instead of
    /// polling `snapshots()`; the stream ends when the reader stops reading it.
    public func snapshotUpdates() -> AsyncStream<[TunnelSnapshot]> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: [TunnelSnapshot].self, bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        observers[key] = continuation
        continuation.onTermination = { _ in
            Task { await self.removeObserver(key) }
        }
        continuation.yield(snapshots())
        return stream
    }

    /// Sends the current snapshots to every reader of `snapshotUpdates()`.
    func publishSnapshots() {
        guard !observers.isEmpty else { return }
        let current = snapshots()
        for continuation in observers.values { continuation.yield(current) }
    }

    private func removeObserver(_ key: UUID) {
        observers[key] = nil
    }
}
