import Darwin
import Foundation
import JerdFoundation
import os

/// A small HTTP server on `127.0.0.1` and a kernel-chosen port above 1023, for transport tests.
/// One thread answers each connection with the bytes of the handler, then closes it.
final class LoopbackHTTPServer: Sendable {
    /// One received request: the head (request line and headers) and the body.
    struct Request: Sendable {
        let head: String
        let body: Data

        var requestLine: String { head.components(separatedBy: "\r\n").first ?? "" }
    }

    typealias Handler = @Sendable (Request) -> Data

    let port: UInt16
    private let descriptor: Int32
    private let received = OSAllocatedUnfairLock<[Request]>(initialState: [])

    init(handler: @escaping Handler) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
            }
        }
        guard descriptor >= 0, bound, listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw JerdError.unavailable("Cannot start the test HTTP server.")
        }
        self.descriptor = descriptor
        port = UInt16(bigEndian: address.sin_port)
        let received = received
        Thread {
            while case let client = accept(descriptor, nil, nil), client >= 0 {
                let request = Self.read(client)
                received.withLock { $0.append(request) }
                _ = handler(request).withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
                close(client)
            }
        }.start()
    }

    /// Every request so far.
    var requests: [Request] { received.withLock { $0 } }

    func stop() {
        shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
    }

    /// A complete HTTP/1.1 answer that closes the connection.
    static func response(status: Int, headers: [String] = [], body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) Test\r\nConnection: close\r\n"
        if !headers.contains(where: { $0.lowercased().hasPrefix("content-length") }) {
            head += "Content-Length: \(body.count)\r\n"
        }
        head += headers.map { "\($0)\r\n" }.joined() + "\r\n"
        return Data(head.utf8) + body
    }

    private static func read(_ client: Int32) -> Request {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let end = data.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
                let body = data[end.upperBound...]
                if body.count >= contentLength(head) { return Request(head: head, body: Data(body)) }
            }
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { return Request(head: String(decoding: data, as: UTF8.self), body: Data()) }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    private static func contentLength(_ head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }
}
