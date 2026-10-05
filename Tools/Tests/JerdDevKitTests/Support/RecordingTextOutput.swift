import os

@testable import JerdDevKit

/// Records everything that the tool writes, per channel.
final class RecordingTextOutput: TextOutput {
    private let state = OSAllocatedUnfairLock(initialState: [(channel: OutputChannel, text: String)]())

    func write(_ text: String, to channel: OutputChannel) {
        state.withLock { $0.append((channel, text)) }
    }

    var standardOutput: String { text(of: .standardOutput) }
    var standardError: String { text(of: .standardError) }
    var all: String { state.withLock { $0.map(\.text).joined() } }

    private func text(of channel: OutputChannel) -> String {
        state.withLock { $0.filter { $0.channel == channel }.map(\.text).joined() }
    }
}
