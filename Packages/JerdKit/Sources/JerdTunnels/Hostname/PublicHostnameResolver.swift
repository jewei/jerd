import Darwin

/// The system resolver (`getaddrinfo`), as a browser uses it. It runs off the caller's executor,
/// because a lookup can block for some seconds.
public struct PublicHostnameResolver: PublicHostnameResolving {
    public init() {}

    public func status(of hostname: String) async -> PublicHostnameStatus {
        await Task.detached(priority: .utility) { Self.lookUp(hostname) }.value
    }

    private static func lookUp(_ hostname: String) -> PublicHostnameStatus {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &result)
        defer { if let result { freeaddrinfo(result) } }
        var count = 0
        var current = status == 0 ? result : nil
        while let entry = current {
            count += 1
            current = entry.pointee.ai_next
        }
        return PublicHostnameStatus.classify(status: status, addressCount: count)
    }
}
