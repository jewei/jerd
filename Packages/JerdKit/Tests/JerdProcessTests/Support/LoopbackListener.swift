import Darwin
import Foundation
import JerdFoundation

/// A listening TCP socket on 127.0.0.1 with an ephemeral port, closed on release.
struct LoopbackListener {
    let handle: FileHandle
    let port: UInt16

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                bind(descriptor, raw, length) == 0 && listen(descriptor, 1) == 0
                    && getsockname(descriptor, raw, &length) == 0
            }
        }
        guard descriptor >= 0, bound else { throw JerdError.unavailable("Cannot create a test listener.") }
        port = UInt16(bigEndian: address.sin_port)
    }
}
