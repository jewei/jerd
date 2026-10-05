import Foundation
import os

/// The machine-readable summary of one command for `--json`. The console and the step sequence record
/// into the task-local `current` report, so no command needs an extra parameter.
final class RunReport: Sendable {
    @TaskLocal static var current: RunReport?

    /// One `ok:`, `warning:`, `error:`, or detail line of the console.
    struct Message: Codable, Equatable, Sendable {
        var level: String
        var text: String
    }

    struct Step: Codable, Equatable, Sendable {
        var title: String
        var status: String
        var seconds: Double
        var messages: [Message]
    }

    /// The JSON object. `message` is `null` when the command succeeded.
    struct Summary: Codable, Equatable, Sendable {
        var command: String
        var status: String
        var exitStatus: Int32
        var message: String?
        var steps: [Step]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(command, forKey: .command)
            try container.encode(status, forKey: .status)
            try container.encode(exitStatus, forKey: .exitStatus)
            try container.encode(message, forKey: .message)
            try container.encode(steps, forKey: .steps)
        }
    }

    private struct State {
        var steps: [Step] = []
        var pendingMessages: [Message] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func record(level: String, text: String) {
        state.withLock { $0.pendingMessages.append(Message(level: level, text: text)) }
    }

    /// Ends the current step. The messages since the last step belong to it.
    func finishStep(title: String, status: ExitStatus, duration: Duration) {
        let seconds = (Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        let rounded = (seconds * 1000).rounded() / 1000
        state.withLock { state in
            state.steps.append(
                Step(title: title, status: status.label, seconds: rounded, messages: state.pendingMessages))
            state.pendingMessages = []
        }
    }

    func summary(command: String, status: ExitStatus, message: String?) -> Summary {
        Summary(
            command: command, status: status.label, exitStatus: status.rawValue, message: message,
            steps: state.withLock { $0.steps })
    }

    /// One line of JSON with sorted keys, so that the field order is stable.
    static func encoded(_ summary: Summary) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(summary) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
