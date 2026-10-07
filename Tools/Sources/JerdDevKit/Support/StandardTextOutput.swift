import Foundation

/// Writes unbuffered to the standard output and standard error of `./dev`, so that the tool's own
/// lines and the streamed lines of child processes stay in order.
/// With `--json`, standard output carries only the JSON summary, so every other line goes to standard error.
struct StandardTextOutput: TextOutput {
    var sendsEverythingToStandardError = false

    func write(_ text: String, to channel: OutputChannel) {
        let toOutput = channel == .standardOutput && !sendsEverythingToStandardError
        let handle: FileHandle = toOutput ? .standardOutput : .standardError
        handle.write(Data(text.utf8))
    }
}
