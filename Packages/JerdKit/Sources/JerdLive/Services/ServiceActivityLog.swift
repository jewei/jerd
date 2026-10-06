import os

/// Writes each start and stop request of a service to the unified log, so a later look at
/// `log show --predicate 'subsystem == "dev.jerd.app"'` shows what started a process and when.
/// The live ports call it only from the request methods: a load or a snapshot never logs a start.
package enum ServiceActivityLog {
    static let log = Logger(subsystem: "dev.jerd.app", category: "services")

    package static func request(_ action: String, _ service: String) {
        log.notice("\(action, privacy: .public) requested for \(service, privacy: .public).")
    }
}
