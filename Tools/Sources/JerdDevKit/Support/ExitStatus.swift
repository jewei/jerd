/// The stable exit codes of `./dev`. CI and scripts depend on these values.
public enum ExitStatus: Int32, Sendable, CaseIterable {
    case success = 0
    case checkFailed = 1
    case usage = 2
    case missingPrerequisite = 3

    /// The more severe of two results. A missing prerequisite outranks a failed check
    /// because the user must fix the machine before any check result is reliable.
    func combined(with other: ExitStatus) -> ExitStatus {
        severity >= other.severity ? self : other
    }

    private var severity: Int {
        switch self {
        case .success: 0
        case .checkFailed: 1
        case .missingPrerequisite: 2
        case .usage: 3
        }
    }
}
