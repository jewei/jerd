import Darwin
import Foundation
import JerdFoundation

/// Two bound loopback TCP listeners that a child inherits as descriptors 3 (HTTP) and 4 (HTTPS).
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

    /// Requires both handles to be bound IPv4 loopback TCP sockets with a non-zero port.
    func validate() throws {
        for handle in [http, https] where !Self.isLoopbackTCPListener(handle.fileDescriptor) {
            throw JerdError.invalid("Expected a bound IPv4 loopback TCP socket.")
        }
    }

    private static func isLoopbackTCPListener(_ descriptor: Int32) -> Bool {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        var type: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        return named == 0 && address.sin_family == sa_family_t(AF_INET)
            && address.sin_addr.s_addr == in_addr_t(0x7F00_0001).bigEndian && address.sin_port != 0
            && getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &size) == 0 && type == SOCK_STREAM
    }
}
