import Darwin
import Dispatch
import Foundation
import JerdFoundation
import os

/// A pipe between a child and its log that removes secrets before any byte reaches the disk.
///
/// The child writes into `writer`. One serial queue reads at most 1 MiB per event (64 reads of
/// 16 KiB), so a busy child cannot hold the queue, and appends the redacted bytes to the log.
/// A failed log write stops further output and is reported by `writeFailure`.
final class RedactingPipe: Sendable {
    private struct Streams: Sendable {
        var redactor: LogRedactor
        var reader: Int32
        var log: Int32?
        var reachedEnd = false
        var writeFailure: Int32?
    }

    /// The write end for the child's standard output and standard error.
    let writer: Int32
    private let parentWriter: OSAllocatedUnfairLock<Int32?>
    private let streams: OSAllocatedUnfairLock<Streams>
    private let queue = DispatchQueue(label: "dev.jerd.redacting-pipe", qos: .utility)
    private let source: any DispatchSourceRead

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
        streams = OSAllocatedUnfairLock(initialState: Streams(redactor: redactor, reader: ends[0], log: duplicate))
        source = DispatchSource.makeReadSource(fileDescriptor: ends[0], queue: queue)
        let reader = ends[0]
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(reader) }
        source.resume()
    }

    /// Closes Jerd's copy of the write end after the spawn, so the child alone holds it. Idempotent.
    func closeParentWriter() {
        parentWriter.withLock { value in
            if let open = value { close(open) }
            value = nil
        }
    }

    /// Drains what is left, releases held bytes, and closes the pipe and the log duplicate. Idempotent.
    func finish() {
        closeParentWriter()
        queue.sync {
            drain()
            streams.withLock { state in
                Self.write(state.redactor.append(Data(), final: true), into: &state)
                if let log = state.log { close(log) }
                state.log = nil
            }
        }
        source.cancel()
    }

    /// The system error text of a failed log write, or nil.
    var writeFailure: String? {
        streams.withLock { $0.writeFailure.map(SystemError.describe) }
    }

    private func drain() {
        streams.withLock { state in
            guard state.log != nil, !state.reachedEnd else { return }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            for _ in 0..<64 {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(state.reader, $0.baseAddress, $0.count) }
                if count > 0 {
                    Self.write(state.redactor.append(Data(bytes[0..<count])), into: &state)
                } else if count == 0 {
                    // End of file: every writer closed. Stop the source, which would fire again and again.
                    state.reachedEnd = true
                    Self.write(state.redactor.append(Data(), final: true), into: &state)
                    source.cancel()
                    return
                } else if errno != EINTR {
                    return
                }
            }
        }
    }

    private static func write(_ data: Data, into state: inout Streams) {
        guard let log = state.log, state.writeFailure == nil, !data.isEmpty else { return }
        let failure = DescriptorIO.writeAll(data, to: log)
        if failure != 0 { state.writeFailure = failure }
    }
}
