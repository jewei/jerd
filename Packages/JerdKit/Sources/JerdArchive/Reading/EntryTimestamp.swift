import Darwin

/// The modification time that an archive entry records. Build tools such as `make` compare these times.
package struct EntryTimestamp: Sendable, Equatable {
    package var seconds: Int64
    /// The fraction of the second, 0 to 999,999,999.
    package var nanoseconds: Int

    package init(seconds: Int64, nanoseconds: Int = 0) {
        self.seconds = seconds
        self.nanoseconds = min(max(nanoseconds, 0), 999_999_999)
    }

    /// The time as a `timespec` for `futimens`.
    var timespec: Darwin.timespec {
        Darwin.timespec(tv_sec: time_t(seconds), tv_nsec: nanoseconds)
    }
}
