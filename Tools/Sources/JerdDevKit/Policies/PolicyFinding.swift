/// One violation of a repository policy, with the file that has the problem.
struct PolicyFinding: Equatable, Sendable, CustomStringConvertible {
    /// The path relative to the repository root.
    var file: String
    var message: String

    var description: String { "\(file): \(message)" }
}
