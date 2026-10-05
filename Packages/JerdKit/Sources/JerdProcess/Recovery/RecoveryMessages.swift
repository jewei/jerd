/// The user texts of process recovery rows.
enum RecoveryMessages {
    static let stale = "The saved process has exited or its PID was reused. Clear this stale record to retry Start."

    static func legacy(_ pid: Int32) -> String {
        "Legacy process record for PID \(pid). Ownership cannot be proved. Inspect its executable and stop the "
            + "service manually; Jerd will not signal this PID."
    }

    static func managed(_ pid: Int32) -> String {
        "A running Jerd session manages PID \(pid). Use its normal Stop control."
    }

    static func uncertain(_ pid: Int32) -> String {
        "Ownership of PID \(pid) is uncertain. The record and data were preserved. Inspect this service manually."
    }

    static func recoverable(_ record: ActiveRunRecord, _ identity: ProcessIdentity) -> String {
        "\(record.runtimeID) · PID \(record.processID)\n\(identity.executable)\nThe previous Jerd session ended. "
            + "Request a graceful stop, then retry Start."
    }
}
