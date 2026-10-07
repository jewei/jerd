import Darwin
import Dispatch
import Foundation
import JerdFoundation
import os

/// The read side of a `RedactingPipe`: the reader, the redactor, and the log duplicate.
///
/// `@unchecked Sendable` is safe because every stored property is read and written only on
/// `queue`, a serial queue: the read source runs its handlers there, and `RedactingPipe` reaches
/// the stream only through `queue.async`. Only `failure` is shared, through its own lock.
final class RedactingStream: @unchecked Sendable {
    /// Reads per event: 64 reads of 16 KiB, so one busy child cannot hold the queue.
    static let readsPerEvent = 64
    static let readSize = 16_384

    let queue: DispatchQueue
    /// The `errno` of the first failed log write. Later output is dropped.
    let failure = OSAllocatedUnfairLock<Int32?>(initialState: nil)
    private let reader: Int32
    private var redactor: LogRedactor
    private var log: Int32?
    private var reachedEnd = false
    /// Strong until the end of file, so that a writer outside the group can still write after
    /// `finish`. The cancel handler breaks the cycle.
    private var source: (any DispatchSourceRead)?

    init(reader: Int32, log: Int32, redactor: LogRedactor, queue: DispatchQueue) {
        self.reader = reader
        self.log = log
        self.redactor = redactor
        self.queue = queue
    }

    /// Starts reading. Call once.
    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: reader, queue: queue)
        let reader = reader
        source.setEventHandler { [self] in drain() }
        source.setCancelHandler { [self] in
            close(reader)
            self.source = nil
        }
        self.source = source
        source.resume()
    }

    /// Reads what is available. At the end of file it flushes held bytes and stops the source.
    func drain() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !reachedEnd else { return }
        var bytes = [UInt8](repeating: 0, count: Self.readSize)
        for _ in 0..<Self.readsPerEvent {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(reader, $0.baseAddress, $0.count) }
            if count > 0 {
                write(redactor.append(Data(bytes[0..<count])))
            } else if count == 0 {
                // Every writer closed. Stop the source, which would fire again and again.
                reachedEnd = true
                closeLog()
                source?.cancel()
                return
            } else if errno != EINTR {
                return
            }
        }
    }

    /// Drains what is there now, flushes held bytes, and closes the log. The reader stays open
    /// until the end of file: a process outside the group that still holds the writer gets no
    /// `SIGPIPE`, and its later output is read and dropped.
    func finish() {
        dispatchPrecondition(condition: .onQueue(queue))
        drain()
        closeLog()
    }

    private func closeLog() {
        write(redactor.append(Data(), final: true))
        if let log { close(log) }
        log = nil
    }

    private func write(_ data: Data) {
        guard let log, failure.withLock({ $0 == nil }), !data.isEmpty else { return }
        let code = DescriptorIO.writeAll(data, to: log)
        if code != 0 { failure.withLock { $0 = code } }
    }
}
