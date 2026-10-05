import Darwin
import Foundation
import JerdFoundation

/// The system HTTPS check: normal name resolution, normal macOS trust, no custom CA, no bypass.
///
/// Rules: the hostname must resolve, and only to `127.0.0.1`; the request uses an ephemeral session
/// without proxies or redirects; the answer must be status 200 with the exact readiness body.
public struct SystemTrustProbe: TrustProbing {
    /// The numeric addresses of a hostname, or nil when it does not resolve.
    public typealias Resolve = @Sendable (String) -> [String]?
    /// The status and body of an HTTPS GET.
    public typealias Fetch = @Sendable (URL) async throws -> (status: Int, body: Data)

    private let resolve: Resolve
    private let fetch: Fetch

    public init(resolve: @escaping Resolve = Self.systemResolve, fetch: @escaping Fetch = Self.systemFetch) {
        self.resolve = resolve
        self.fetch = fetch
    }

    public func check(hostname: String) async throws {
        let host = try HostnamePolicy.validate(hostname).value
        guard let addresses = resolve(host), !addresses.isEmpty else {
            throw JerdError.unavailable(
                "The hostname does not resolve yet. Retry Start after macOS updates its host cache.")
        }
        guard addresses.allSatisfy({ $0 == "127.0.0.1" }) else {
            throw JerdError.unavailable("The hostname must resolve only to 127.0.0.1.")
        }
        guard let url = URL(string: "https://\(host)\(SiteRoutePolicy.healthPath)") else {
            throw JerdError.invalid("Use a hostname ending in .test, without spaces or a port.")
        }
        let (status, body) = try await fetch(url)
        guard status == 200, String(data: body, encoding: .utf8) == SiteRoutePolicy.healthResponse else {
            throw JerdError.unavailable("The system HTTPS check did not receive Jerd's response.")
        }
    }

    /// `getaddrinfo` with any family. IPv4 results are dotted text, IPv6 results are `inet_ntop` text.
    public static let systemResolve: Resolve = { host in
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current?.pointee {
            addresses.append(numericHost(entry) ?? "?")
            current = entry.ai_next
        }
        return addresses
    }

    /// An ephemeral session: no proxy, 5 s per request, 8 s in total, and no redirects.
    public static let systemFetch: Fetch = { url in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private static func numericHost(_ entry: addrinfo) -> String? {
        guard let address = entry.ai_addr else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, entry.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Refuses every redirect, so the check reads Jerd's own answer or fails.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? { nil }
}
