import Foundation
import Darwin

/// Retains only a bounded suffix, so credentials split between writes cannot
/// reach the log. Match bytes before decoding text or writing to disk.
struct LogRedactor {
    private let secrets: [[UInt8]]
    private var pending: [UInt8] = []

    init(values: [String]) {
        secrets = Array(Set(values.filter { !$0.isEmpty })).map { Array($0.utf8) }.sorted { $0.count > $1.count }
    }

    mutating func append(_ bytes: Data, final: Bool = false) -> Data {
        pending.append(contentsOf: bytes)
        var output = Data()
        var index = 0
        while index < pending.count {
            let remaining = pending.count - index
            // Delay only a possible credential prefix, not ordinary recent output.
            // Check this before complete matches so overlapping secrets stay private.
            if !final && secrets.contains(where: {
                remaining < $0.count && pending[index...].elementsEqual($0.prefix(remaining))
            }) { break }
            if let secret = secrets.first(where: {
                pending.count - index >= $0.count && pending[index..<(index + $0.count)].elementsEqual($0)
            }) {
                output.append(contentsOf: "[REDACTED]".utf8)
                index += secret.count
            } else {
                output.append(pending[index])
                index += 1
            }
        }
        pending.removeFirst(index)
        return output
    }
}

/// Only requests containing secrets use a pipe. All pipe reads and log writes
/// run on one utility queue. Ordinary services retain direct append logs.
final class RedactedProcessLog: @unchecked Sendable {
    let writer: Int32
    private let reader: Int32
    private let log: Int32
    private let queue = DispatchQueue(label: "dev.jerd.redacted-log", qos: .utility)
    private var source: DispatchSourceRead?
    private var redactor: LogRedactor
    private var finished = false
    private var reachedEnd = false
    private var writeFailed = false

    init(log: Int32, values: [String]) throws {
        guard values.count <= 32, values.allSatisfy({ $0.utf8.count <= 65_536 }) else {
            throw JerdError.invalid("The log redaction configuration is too large.")
        }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw JerdError.process("Cannot create a private process log pipe.") }
        let duplicate = fcntl(log, F_DUPFD_CLOEXEC, 64)
        guard duplicate >= 0 else {
            close(descriptors[0]); close(descriptors[1])
            throw JerdError.process("Cannot open a private process log.")
        }
        reader = descriptors[0]; writer = descriptors[1]; self.log = duplicate
        redactor = LogRedactor(values: values)
        guard fcntl(reader, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(writer, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(reader, F_SETFL, O_NONBLOCK) == 0 else {
            close(reader); close(writer); close(duplicate)
            throw JerdError.process("Cannot configure the private process log pipe.")
        }
    }

    func start() {
        queue.sync {
            let source = DispatchSource.makeReadSource(fileDescriptor: reader, queue: queue)
            source.setEventHandler { [weak self] in self?.drain() }
            // The cancelled source owns the reader until its final event ends.
            let reader = reader
            source.setCancelHandler { close(reader) }
            self.source = source
            source.resume()
        }
    }

    func closeParentWriter() { close(writer) }

    func finish() {
        queue.sync {
            guard !finished else { return }
            drain()
            write(redactor.append(Data(), final: true))
            finished = true
            if let source { source.cancel(); self.source = nil }
            else { close(reader) }
            close(log)
        }
    }

    private func drain() {
        guard !finished, !reachedEnd else { return }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        // Avoid monopolizing the queue when a child writes continuously.
        for _ in 0..<64 {
            let count = Darwin.read(reader, &bytes, bytes.count)
            if count > 0 {
                write(redactor.append(Data(bytes.prefix(count))))
            } else if count == 0 {
                reachedEnd = true
                write(redactor.append(Data(), final: true))
                source?.cancel()
                return
            } else if errno != EINTR {
                return
            }
        }
    }

    private func write(_ data: Data) {
        guard !writeFailed else { return }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(log, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { writeFailed = true; return }
                offset += count
            }
        }
    }
}
