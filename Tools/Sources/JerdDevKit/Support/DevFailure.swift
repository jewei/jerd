/// A failure that ends a command with a stable exit status and a message that the user can act on.
struct DevFailure: Error, Equatable, Sendable, CustomStringConvertible {
    let status: ExitStatus
    let message: String

    var description: String { message }

    static func checkFailed(_ message: String) -> DevFailure {
        DevFailure(status: .checkFailed, message: message)
    }

    static func usage(_ message: String) -> DevFailure {
        DevFailure(status: .usage, message: message)
    }

    static func missingPrerequisite(_ message: String) -> DevFailure {
        DevFailure(status: .missingPrerequisite, message: message)
    }
}
