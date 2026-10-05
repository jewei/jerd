import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// Two bound, listening IPv4 loopback sockets on ephemeral ports, like the helper's 80 and 443.
struct TestListeners {
    let inherited: InheritedListeners
    let httpPort: UInt16
    let httpsPort: UInt16

    init() throws {
        let http = try Self.bind()
        let https = try Self.bind()
        inherited = InheritedListeners(http: http.handle, https: https.handle)
        httpPort = http.port
        httpsPort = https.port
    }

    func close() {
        try? inherited.http.close()
        try? inherited.https.close()
    }

    /// One listener. `SO_REUSEADDR` and never `SO_REUSEPORT`, like the helper.
    static func bind(listening: Bool = true) throws -> (handle: FileHandle, port: UInt16) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot create a test listener.") }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                Darwin.bind(descriptor, raw, length) == 0 && (!listening || listen(descriptor, 128) == 0)
                    && getsockname(descriptor, raw, &length) == 0
            }
        }
        guard bound else {
            Darwin.close(descriptor)
            throw JerdError.unavailable("Cannot bind a test listener.")
        }
        return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), UInt16(bigEndian: address.sin_port))
    }
}
