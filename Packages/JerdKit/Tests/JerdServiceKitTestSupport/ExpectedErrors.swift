import Darwin
import JerdFoundation

/// Exact errors that the service test targets expect, so a refusal for another reason fails.
package enum ExpectedErrors {
    /// The start gate refuses a run record of this test process (a live PID that Jerd cannot prove
    /// stale).
    package static var liveRecordOfThisProcess: JerdError {
        .unavailable(
            "A previous service process needs inspection (PID \(getpid())). Open Advanced → Process recovery. "
                + "No process was signalled.")
    }

    /// True when `error` is a `DecodingError` for the missing key `key`.
    package static func isMissingKey(_ error: any Error, _ key: String) -> Bool {
        guard case DecodingError.keyNotFound(let missing, _) = error else { return false }
        return missing.stringValue == key
    }
}
