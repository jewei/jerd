/// The quiet filter of a `swift test` run. It shows failures with their details, diagnostics, and the
/// final count. It hides build progress, "started" events, the run header, and one line for each
/// passed test or suite. It keeps state because one event can span lines:
/// - The `↳` lines after a `✘` line hold the comment and the values of a failed expectation.
/// - A test argument with a line break continues a "◇ … started." event on the next lines.
struct QuietTestOutput: LineFiltering {
    private enum State {
        case normal
        /// Inside a hidden "started" event that has not reached its last line.
        case hiddenEvent
        /// After a failure line: its `↳` details stay visible.
        case failureDetails
    }

    private var state = State.normal

    mutating func shows(_ line: String) -> Bool {
        if state == .hiddenEvent {
            if line.hasSuffix(" started.") { state = .normal }
            return false
        }
        if line.hasPrefix("✘ ") {
            state = .failureDetails
            return true
        }
        if line.hasPrefix("↳ ") {
            return state == .failureDetails
        }
        if line.hasPrefix("◇ ") {
            state = line.hasSuffix(" started.") ? .normal : .hiddenEvent
            return false
        }
        if line.hasPrefix("✔ ") {
            state = .normal
            return line.hasPrefix("✔ Test run ")
        }
        return Self.showsOtherLine(line)
    }

    /// Lines that are not Swift Testing events: build progress, XCTest lines, and everything else.
    private static func showsOtherLine(_ line: String) -> Bool {
        if SwiftPMOutput.isProgress(line) || line.hasPrefix("\t Executed ") {
            return false
        }
        // XCTest also reports its empty run. Keep only its failures.
        if line.hasPrefix("Test Suite '") || line.hasPrefix("Test Case '") {
            return line.contains(" failed")
        }
        return true
    }
}
