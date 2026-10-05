/// One line of the `doctor` report.
struct DoctorFinding: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case ok
        /// Present, but not the version that the repository is tested with.
        case warning
        /// Absent or unusable. The message has the install hint.
        case missing
        /// Optional programs. Their absence never fails `doctor`.
        case information
    }

    var prerequisite: Prerequisite
    var level: Level
    var message: String
}
