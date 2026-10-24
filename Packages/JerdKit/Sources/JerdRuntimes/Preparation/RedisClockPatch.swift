import Foundation
import JerdFoundation

/// Makes Redis use POSIX `clock_gettime` on arm64 instead of the raw CPU counter.
///
/// Redis 8 reads `CNTVCT_EL0` directly on arm64, and no build flag turns that off. macOS can reset
/// this counter in a deep sleep; it keeps `mach_absolute_time` steady with a kernel offset that
/// Redis does not read. The deadline of the Redis timer then lies far in the future: Redis still
/// answers clients, but it stops its periodic saves and ignores `SIGTERM`. The patch guards the
/// counter code with `USE_PROCESSOR_CLOCK`, as Redis does on x86 and RISC-V.
package enum RedisClockPatch {
    /// The source file with the clock selection, relative to the source root.
    package static let file = "src/monotonic.c"
    package static let counterGuard = "#if defined(__aarch64__)"
    package static let patchedGuard = "#if defined(USE_PROCESSOR_CLOCK) && defined(__aarch64__)"
    /// The counter functions and their selection in `monotonicInit`.
    package static let guardCount = 2
    /// The source is larger than 10 KB; this limit only bounds the read.
    static let sizeLimit = 1_000_000
    package static let unexpectedSource = JerdError.invalid(
        "This Redis version changed its clock code, so Jerd cannot build it safely yet. Keep the current Redis version, or update Jerd."
    )

    /// Pure: the text with each counter guard replaced.
    /// - Throws: `unexpectedSource` unless the text has exactly `guardCount` counter guards.
    package static func apply(to text: String) throws -> String {
        guard text.components(separatedBy: counterGuard).count == guardCount + 1 else { throw unexpectedSource }
        return text.replacingOccurrences(of: counterGuard, with: patchedGuard)
    }

    /// Patches `file` in the extracted source at `source`.
    package static func apply(in source: URL) throws {
        let url = source.appendingPathComponent(file)
        guard FileProbe.presence(at: url) == .present,
            let text = String(data: try AtomicFile.read(url, limit: sizeLimit), encoding: .utf8)
        else { throw unexpectedSource }
        try AtomicFile.write(Data(try apply(to: text).utf8), to: url)
    }
}
