/// Where the tool writes text. The live type writes to the terminal; tests record the text.
protocol TextOutput: Sendable {
    func write(_ text: String, to channel: OutputChannel)
}
