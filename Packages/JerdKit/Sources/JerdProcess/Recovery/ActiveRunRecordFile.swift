import Foundation
import JerdFoundation

/// The one reader and writer of active-run record files.
///
/// Encoding is `JSONFileFormat.compact` (the old `JSONEncoder()` defaults). Reads are bounded,
/// owner-checked, and refuse links. A write checks every limit before it touches the file, so a
/// refused write leaves the previous record readable.
public enum ActiveRunRecordFile {
    /// Reads and checks a record.
    /// - Throws: `.corrupt` for an invalid record, which stays in place for inspection.
    public static func read(_ file: URL) throws -> ActiveRunRecord {
        let data = try AtomicFile.read(file, limit: ActiveRunRecord.maximumBytes)
        let record: ActiveRunRecord
        do {
            record = try JSONDecoder().decode(ActiveRunRecord.self, from: data)
        } catch {
            throw invalid(FailureDetail.describe(error))
        }
        guard record.isWellFormed else {
            throw invalid("The process IDs or the number of service processes are invalid.")
        }
        return record
    }

    /// Writes a record after checking the descendant and size limits.
    public static func write(_ record: ActiveRunRecord, to file: URL) throws {
        guard (record.descendants?.count ?? 0) <= ActiveRunRecord.maximumDescendants else {
            throw JerdError.unavailable(
                "Too many service processes to save for recovery. The previous record was preserved. No process was signalled."
            )
        }
        let data = try JSONFileFormat.compact.makeEncoder().encode(record)
        guard data.count <= ActiveRunRecord.maximumBytes else {
            throw JerdError.unavailable(
                "The service recovery record is too large. The previous record was preserved. No process was signalled."
            )
        }
        try AtomicFile.write(data, to: file)
    }

    /// Deletes the record of `location`. Only the holder of its lock can do this.
    public static func remove(_ location: RecordLocation, holding lock: InstanceLock) throws {
        try requireHeld(lock, for: location)
        try AtomicFile.remove(location.recordFile)
    }

    /// Requires `lock` to be held and to be the lock of `location`.
    static func requireHeld(_ lock: InstanceLock, for location: RecordLocation) throws {
        guard lock.guards(location.lockFile) else {
            throw JerdError.invalid("Hold the lock of \(location.id) before changing its process record.")
        }
    }

    private static func invalid(_ detail: String) -> JerdError {
        .corrupt("The saved process record is invalid. It was preserved. \(detail)")
    }
}
