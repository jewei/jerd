import Foundation
import os

/// Collects the bytes of one output channel from the pipe callback thread, and prints the lines that
/// the output mode selects. It keeps at least the last `byteLimit` bytes: the end of a long log
/// explains a failure. It trims only when the buffer is twice the limit, so it copies rarely.
final class OutputCollector: Sendable {
    private struct State {
        var data = Data()
        var splitter = LineSplitter()
        var filter: (any LineFiltering)?
    }

    private let state: OSAllocatedUnfairLock<State>
    private let channel: OutputChannel
    private let prints: Bool
    private let output: any TextOutput
    private let byteLimit: Int

    init(channel: OutputChannel, mode: OutputMode, output: any TextOutput, byteLimit: Int = 16 << 20) {
        self.channel = channel
        self.prints = mode.prints
        self.output = output
        self.byteLimit = byteLimit
        self.state = OSAllocatedUnfairLock(initialState: State(filter: mode.filter))
    }

    func append(_ data: Data) {
        let limit = byteLimit
        let prints = prints
        let lines = state.withLock { state -> [String] in
            state.data.append(data)
            if state.data.count > 2 * limit {
                state.data = Data(state.data.suffix(limit))
            }
            return prints ? Self.selected(state.splitter.append(data), state: &state) : []
        }
        emit(lines)
    }

    /// Prints a last line that has no line break.
    func finish() {
        let prints = prints
        let lines = state.withLock { state -> [String] in
            guard prints, let last = state.splitter.finish() else { return [] }
            return Self.selected([last], state: &state)
        }
        emit(lines)
    }

    /// The captured text: at most the last `byteLimit` bytes.
    var text: String {
        let limit = byteLimit
        return state.withLock { String(decoding: $0.data.suffix(limit), as: UTF8.self) }
    }

    private static func selected(_ lines: [String], state: inout State) -> [String] {
        guard var filter = state.filter else { return lines }
        defer { state.filter = filter }
        return lines.filter { filter.shows($0) }
    }

    private func emit(_ lines: [String]) {
        for line in lines {
            output.write(line + "\n", to: channel)
        }
    }
}
