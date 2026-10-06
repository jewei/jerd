import Darwin
import Dispatch
import Foundation
import JerdFoundation
import os

/// A pipe between a child and its log that removes secrets before any byte reaches the disk.
///
/// The child writes into `writer`. A `RedactingStream` on one serial queue reads at most 1 MiB per
/// event and appends the redacted bytes to the log. No lock is held across a system call, and
/// `finish` waits without blocking a thread. A failed log write stops further output and is
/// reported by `writeFailure`.
final class RedactingPipe: Sendable {
    /// The write end for the child's standard output and standard error.
    let writer: Int32
    private let parentWriter: OSAllocatedUnfairLock<Int32?>
    private let stream: RedactingStream

    /// Creates the pipe and a private duplicate of `log` (at 64 or above, close-on-exec).
    init(log: Int32, values: [String]) throws {
        let redactor = try LogRedactor(values: values)
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { throw JerdError.processFailed("Cannot create a private process log pipe.") }
        let duplicate = fcntl(log, F_DUPFD_CLOEXEC, 64)
        guard duplicate >= 0 else {
            ends.forEach { close($0) }
            throw JerdError.processFailed("Cannot open a private process log.")
        }
        guard fcntl(ends[0], F_SETFD, FD_CLOEXEC) == 0, fcntl(ends[1], F_SETFD, FD_CLOEXEC) == 0,
            fcntl(ends[0], F_SETFL, O_NONBLOCK) == 0
        else {
            (ends + [duplicate]).forEach { close($0) }
            throw JerdError.processFailed("Cannot configure the private process log pipe.")
        }
        writer = ends[1]
        parentWriter = OSAllocatedUnfairLock(initialState: ends[1])
        let queue = DispatchQueue(label: "dev.jerd.redacting-pipe", qos: .utility)
        stream = RedactingStream(reader: ends[0], log: duplicate, redactor: redactor, queue: queue)
        queue.async { [stream] in stream.start() }
    }

    /// Closes Jerd's copy of the write end after the spawn, so the child alone holds it. Idempotent.
    func closeParentWriter() {
        parentWriter.withLock { value in
            if let open = value { close(open) }
            value = nil
        }
    }

    /// Drains what is left, releases held bytes, and closes the log duplicate. Idempotent.
    ///
    /// The reader stays open until every writer closed, so a process that left the group and
    /// still writes gets no `SIGPIPE`; its later output is dropped.
    func finish() async {
        closeParentWriter()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.queue.async { [stream] in
                stream.finish()
                continuation.resume()
            }
        }
    }

    /// The system error text of a failed log write, or nil.
    var writeFailure: String? {
        stream.failure.withLock { $0 }.map(SystemError.describe)
    }
}
