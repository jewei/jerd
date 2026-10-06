import Foundation
import OSLog

/// Reads the app log entries (`dev.jerd.app`) that this test process wrote.
enum AppLogEntries {
    /// The messages of the `services` category since `start`.
    static func serviceMessages(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@", "dev.jerd.app", "services")
        return try store.getEntries(at: store.position(date: start), matching: predicate)
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }
}
