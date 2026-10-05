import Darwin
import JerdFoundation

/// IPv4 loopback socket calls for port checks.
enum LoopbackSocket {
    /// SO_REUSEADDR tolerates connections in TIME_WAIT after a restart. SO_REUSEPORT is never set,
    /// so the bind fails beside another listener on the exact address.
    static func requireBindable(_ port: UInt16) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.processFailed("Cannot create a port check socket.") }
        defer { close(descriptor) }
        var reuse: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw JerdError.processFailed("Cannot configure the port check socket.")
        }
        var address = loopback(port)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            throw JerdError.unavailable("Loopback port \(port) is occupied or cannot be bound. No process was stopped.")
        }
    }

    /// True when a TCP connection to `127.0.0.1:<port>` completes within `timeout`.
    static func accepts(port: UInt16, timeout: Duration) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
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
        let milliseconds = Int32(
            timeout.components.seconds * 1_000 + timeout.components.attoseconds / 1_000_000_000_000_000)
        guard poll(&poller, 1, milliseconds) == 1 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0
    }

    private static func loopback(_ port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        return address
    }
}
