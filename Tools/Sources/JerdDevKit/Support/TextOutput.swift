import Foundation

/// Where the tool writes text. The live type writes to the terminal; tests record the text.
public protocol TextOutput: Sendable {
    func write(_ text: String, to channel: OutputChannel)
}

/// Writes unbuffered to the standard output and standard error of `./dev`, so that the tool's own
/// lines and the streamed lines of child processes stay in order.
public struct StandardTextOutput: TextOutput {
    public init() {}

    public func write(_ text: String, to channel: OutputChannel) {
        let handle: FileHandle = channel == .standardOutput ? .standardOutput : .standardError
        handle.write(Data(text.utf8))
    }
}
