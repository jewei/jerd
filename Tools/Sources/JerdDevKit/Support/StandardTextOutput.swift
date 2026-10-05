import Foundation

/// Writes unbuffered to the standard output and standard error of `./dev`, so that the tool's own
/// lines and the streamed lines of child processes stay in order.
struct StandardTextOutput: TextOutput {
    func write(_ text: String, to channel: OutputChannel) {
        let handle: FileHandle = channel == .standardOutput ? .standardOutput : .standardError
        handle.write(Data(text.utf8))
    }
}
