import Darwin
import JerdFoundation
import JerdProcess

/// Reads the ports of inherited listeners and checks that each one is a listening loopback socket.
public enum ListenerPorts {
    /// The HTTP and HTTPS ports of `listeners`.
    /// - Throws: `.invalid` unless both are bound, listening IPv4 TCP sockets on `127.0.0.1`.
    public static func read(_ listeners: InheritedListeners) throws -> (http: UInt16, https: UInt16) {
        (try port(of: listeners.http.fileDescriptor), try port(of: listeners.https.fileDescriptor))
    }

    /// The TCP state must be LISTEN, not only bound. macOS does not support
    /// `SO_ACCEPTCONN` for `getsockopt`, so the state comes from `TCP_CONNECTION_INFO`.
    static func port(of descriptor: Int32) throws -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0, address.sin_family == sa_family_t(AF_INET),
            address.sin_addr.s_addr == in_addr_t(0x7F00_0001).bigEndian, address.sin_port != 0,
            option(SO_TYPE, of: descriptor) == SOCK_STREAM, isListening(descriptor)
        else { throw JerdError.invalid("Expected a bound IPv4 loopback TCP socket.") }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func isListening(_ descriptor: Int32) -> Bool {
        var info = tcp_connection_info()
        var size = socklen_t(MemoryLayout<tcp_connection_info>.size)
        return getsockopt(descriptor, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &size) == 0
            && Int32(info.tcpi_state) == TCPS_LISTEN
    }

    private static func option(_ name: Int32, of descriptor: Int32) -> Int32? {
        var value: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(descriptor, SOL_SOCKET, name, &value, &size) == 0 ? value : nil
    }
}
