import Foundation
import os

/// Collects the bytes of one output channel from the pipe callback thread, and prints the lines that
/// the output mode selects. It keeps at most `byteLimit` bytes: the end of a long log explains a failure.
final class OutputCollector: Sendable {
    private struct State {
        var data = Data()
        var splitter = LineSplitter()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let channel: OutputChannel
    private let mode: OutputMode
    private let output: any TextOutput
    private let byteLimit: Int

    init(channel: OutputChannel, mode: OutputMode, output: any TextOutput, byteLimit: Int = 16 << 20) {
        self.channel = channel
        self.mode = mode
        self.output = output
        self.byteLimit = byteLimit
    }

    func append(_ data: Data) {
        let lines = state.withLock { state -> [String] in
            state.data.append(data)
            if state.data.count > byteLimit {
                state.data = Data(state.data.suffix(byteLimit))
            }
            return mode.prints ? state.splitter.append(data) : []
        }
        emit(lines)
    }

    /// Prints a last line that has no line break.
    func finish() {
        let last = state.withLock { state -> String? in
            mode.prints ? state.splitter.finish() : nil
        }
        emit(last.map { [$0] } ?? [])
    }

    var text: String {
        state.withLock { String(decoding: $0.data, as: UTF8.self) }
    }

    private func emit(_ lines: [String]) {
        for line in lines where mode.shouldPrint(line) {
            output.write(line + "\n", to: channel)
        }
    }
}
