import Darwin
import Foundation
import JerdFoundation

/// A non-blocking Unix stream socket with one deadline and one cancel signal, for the FPM ping.
struct UnixStreamConnection {
    private let descriptor: Int32
    private let deadline: ContinuousClock.Instant
    private let cancellation: PingCancellation

    /// Connects to `path`. `EAGAIN` (a full backlog) is retried until the deadline.
    static func open(
        path: String, deadline: ContinuousClock.Instant, cancellation: PingCancellation
    ) throws -> UnixStreamConnection {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path), !bytes.contains(0) else {
            throw JerdError.invalid("The FPM probe path is invalid.")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + [0]) }
        while true {
            let descriptor = try makeSocket()
            switch connect(descriptor, &address) {
            case 0:
                let connection = UnixStreamConnection(
                    descriptor: descriptor, deadline: deadline, cancellation: cancellation)
                do {
                    try connection.wait(for: Int16(POLLOUT))
                    try connection.requireConnected()
                } catch {
                    connection.close()
                    throw error
                }
                return connection
            case EAGAIN:
                Darwin.close(descriptor)
                guard ContinuousClock.now < deadline else { throw timedOut }
                try cancellation.check()
                usleep(UInt32(FastCGIPing.slice) * 1_000)
            default:
                Darwin.close(descriptor)
                throw JerdError.processFailed("FPM did not accept its readiness request.")
            }
        }
    }

    /// Sends every byte before the deadline.
    func send(_ data: Data) throws {
        var sent = 0
        while sent < data.count {
            try wait(for: Int16(POLLOUT))
            let count = data.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress?.advanced(by: sent), data.count - sent)
            }
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else { throw JerdError.processFailed("Cannot send the FPM readiness request.") }
            sent += count
        }
    }

    /// The next bytes, or empty data at end of file.
    func receive() throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            try wait(for: Int16(POLLIN))
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count >= 0 else { throw JerdError.processFailed("The FPM readiness connection failed.") }
            return Data(buffer.prefix(count))
        }
    }

    func close() { Darwin.close(descriptor) }

    private func wait(for event: Int16) throws {
        while ContinuousClock.now < deadline {
            try cancellation.check()
            var item = pollfd(fd: descriptor, events: event, revents: 0)
            let result = poll(&item, 1, FastCGIPing.slice)
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw JerdError.processFailed("The FPM readiness connection failed.") }
            if result > 0 { return }
        }
        throw Self.timedOut
    }

    private func requireConnected() throws {
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
            throw JerdError.processFailed("FPM did not accept its readiness request.")
        }
    }

    private static var timedOut: JerdError {
        .processFailed("FPM did not answer its readiness request in time.")
    }

    private static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.processFailed("Cannot create the FPM probe socket.") }
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0,
            fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0, fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0
        else {
            Darwin.close(descriptor)
            throw JerdError.processFailed("Cannot configure the FPM probe socket.")
        }
        return descriptor
    }

    /// 0 when connected or in progress, otherwise the `errno` value.
    private static func connect(_ descriptor: Int32, _ address: inout sockaddr_un) -> Int32 {
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0 || errno == EINPROGRESS ? 0 : errno
    }
}
