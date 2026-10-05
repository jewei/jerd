/// One of the two output streams of a process.
enum OutputChannel: Hashable, Sendable {
    case standardOutput
    case standardError
}
