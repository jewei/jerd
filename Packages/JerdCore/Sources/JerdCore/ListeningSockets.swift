import Foundation
import Darwin

/// Listening descriptors only. No network target or executable crosses the root boundary.
public struct ListeningSockets: Sendable {
    public let http: FileHandle
    public let https: FileHandle
    public init(http: FileHandle, https: FileHandle) { self.http = http; self.https = https }

    public func ports() throws -> (http: UInt16, https: UInt16) {
        (try Self.port(of: http), try Self.port(of: https))
    }

    public func close() {
        try? http.close()
        try? https.close()
    }

    public static func bind(httpPort: UInt16, httpsPort: UInt16) throws -> ListeningSockets {
        guard httpPort != httpsPort || httpPort == 0 else { throw JerdError.invalid("HTTP and HTTPS need different sockets.") }
        let http = try bindOne(httpPort)
        do { return ListeningSockets(http: http, https: try bindOne(httpsPort)) }
        catch { try? http.close(); throw error }
    }

    private static func bindOne(_ port: UInt16) throws -> FileHandle {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.process("Cannot create a loopback listener.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            var reuse: Int32 = 1
            guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                throw JerdError.process("Cannot configure the loopback listener.")
            }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = port.bigEndian
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0, listen(descriptor, 128) == 0 else {
                let detail = String(cString: strerror(errno))
                throw JerdError.unavailable("Loopback port \(port) is occupied or cannot be bound (\(detail)). Stop the other service in its own app, then retry.")
            }
            return handle
        } catch { try? handle.close(); throw error }
    }

    private static func port(of handle: FileHandle) throws -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(handle.fileDescriptor, $0, &length) }
        }
        var socketType: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard result == 0, address.sin_family == AF_INET, address.sin_addr.s_addr == inet_addr("127.0.0.1"),
              address.sin_port != 0,
              getsockopt(handle.fileDescriptor, SOL_SOCKET, SO_TYPE, &socketType, &size) == 0, socketType == SOCK_STREAM else {
            throw JerdError.invalid("Expected a bound IPv4 loopback TCP socket.")
        }
        return UInt16(bigEndian: address.sin_port)
    }
}
