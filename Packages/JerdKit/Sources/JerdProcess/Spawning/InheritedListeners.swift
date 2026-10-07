import Darwin
import Foundation
import JerdFoundation

/// Two listening loopback TCP sockets that a child inherits as descriptors 3 (HTTP) and 4 (HTTPS).
///
/// The caller keeps ownership of both handles. The spawner duplicates them for the child only.
public struct InheritedListeners: Sendable {
    /// The descriptor number of the HTTP listener in the child.
    public static let httpDescriptor: Int32 = 3
    /// The descriptor number of the HTTPS listener in the child.
    public static let httpsDescriptor: Int32 = 4

    public let http: FileHandle
    public let https: FileHandle

    public init(http: FileHandle, https: FileHandle) {
        self.http = http
        self.https = https
    }

    /// Requires both handles to be IPv4 loopback TCP sockets with a non-zero port, in the listening state.
    func validate() throws {
        for handle in [http, https] where !Self.isLoopbackTCPListener(handle.fileDescriptor) {
            throw JerdError.invalid("Expected a listening IPv4 loopback TCP socket.")
        }
    }

    private static func isLoopbackTCPListener(_ descriptor: Int32) -> Bool {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return named == 0 && address.sin_family == sa_family_t(AF_INET)
            && address.sin_addr.s_addr == in_addr_t(0x7F00_0001).bigEndian && address.sin_port != 0
            && isListening(descriptor)
    }

    /// Reads the TCP state through `proc_pidfdinfo`. macOS refuses `SO_ACCEPTCONN` in
    /// `getsockopt`, so the kernel socket information is the only way to see `listen()`.
    static func isListening(_ descriptor: Int32) -> Bool {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(getpid(), descriptor, PROC_PIDFDSOCKETINFO, &info, size) == size else { return false }
        return info.psi.soi_kind == Int32(SOCKINFO_TCP) && info.psi.soi_type == SOCK_STREAM
            && info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
    }
}
