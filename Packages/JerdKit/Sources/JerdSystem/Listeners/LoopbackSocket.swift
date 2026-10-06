import Darwin
import Foundation
import JerdFoundation

/// IPv4 loopback socket calls for the listener pair.
enum LoopbackSocket {
    static let backlog: Int32 = 128

    /// A listening TCP socket on `127.0.0.1:<port>` with `SO_REUSEADDR` (never `SO_REUSEPORT`).
    static func listen(on port: UInt16) throws -> FileHandle {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.processFailed("Cannot create a loopback listener.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var reuse: Int32 = 1
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
            setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0
        else {
            try? handle.close()
            throw JerdError.processFailed("Cannot configure the loopback listener.")
        }
        var address = loopback(port)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, backlog) == 0 else {
            let detail = SystemError.describe(errno)
            try? handle.close()
            throw JerdError.unavailable(
                "Loopback port \(port) is occupied or cannot be bound (\(detail)). "
                    + "Stop the other service in its own app, then retry.")
        }
        return handle
    }

    /// True when a TCP connection to `127.0.0.1:<port>` completes within `timeout` milliseconds.
    /// A wildcard or IPv6 dual-stack listener also accepts it.
    static func accepts(port: UInt16, timeoutMilliseconds: Int32 = 250) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var address = loopback(port)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var poller = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&poller, 1, timeoutMilliseconds) == 1 else { return false }
        var failure: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &failure, &size) == 0 && failure == 0
    }

    /// The port of a bound, listening IPv4 loopback TCP socket.
    static func listeningPort(of descriptor: Int32) throws -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0, address.sin_family == sa_family_t(AF_INET),
            address.sin_addr.s_addr == in_addr_t(0x7F00_0001).bigEndian, address.sin_port != 0,
            option(SO_TYPE, of: descriptor) == SOCK_STREAM, isListening(descriptor)
        else { throw JerdError.invalid("Expected a listening IPv4 loopback TCP socket.") }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func option(_ name: Int32, of descriptor: Int32) -> Int32? {
        var value: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, name, &value, &size) == 0 else { return nil }
        return value
    }

    /// True when the socket is in the listening state (`SO_ACCEPTCONN`). macOS does not answer
    /// `getsockopt(SO_ACCEPTCONN)`, so the flag is read from the kernel's socket information.
    private static func isListening(_ descriptor: Int32) -> Bool {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(getpid(), descriptor, PROC_PIDFDSOCKETINFO, &info, size) == size else { return false }
        return info.psi.soi_options & Int16(SO_ACCEPTCONN) != 0
    }

    private static func loopback(_ port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        address.sin_port = port.bigEndian
        return address
    }
}
