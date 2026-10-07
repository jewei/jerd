import Darwin
import JerdFoundation

/// A loopback port that no socket uses and that the kernel never hands out on its own.
///
/// A closed ephemeral port is not a stable fixture: under parallel load the kernel can give it to
/// the next socket that binds port 0 or connects. A port below the ephemeral range is used only
/// by an explicit bind, so it stays free once a check bind proved it free.
enum UnusedLoopbackPort {
    static func find() throws -> UInt16 {
        let firstEphemeral = ephemeralRangeStart()
        let start = UInt16.random(in: 20_000..<min(firstEphemeral, 40_000))
        for port in start..<firstEphemeral where isFree(port) { return port }
        throw JerdError.unavailable("No unused loopback port below the ephemeral range.")
    }

    /// `net.inet.ip.portrange.first`, or the IANA default 49152.
    private static func ephemeralRangeStart() -> UInt16 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("net.inet.ip.portrange.first", &value, &size, nil, 0) == 0,
            let first = UInt16(exactly: value), first > 40_000
        else { return 49_152 }
        return first
    }

    /// An exclusive bind (no `SO_REUSEADDR`) fails beside any socket on the port.
    private static func isFree(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
