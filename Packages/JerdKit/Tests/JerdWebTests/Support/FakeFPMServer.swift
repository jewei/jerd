import Darwin
import Foundation
import JerdFoundation

/// A Unix socket server that answers each connection with fixed bytes, or stays silent.
///
/// The socket lives in a short folder below `/tmp`, because a socket path must stay below 104 bytes.
final class FakeFPMServer: @unchecked Sendable {
    // Safety: `descriptor` and `folder` are set once in init; the accept loop runs on its own
    // thread and reads only those constants and the immutable `reply`.
    enum Reply {
        /// Read the request, then write these bytes and close.
        case bytes(Data)
        /// Accept and keep the connection open without an answer.
        case silent
        /// Accept and close at once.
        case close
    }

    let folder: URL
    let socket: URL
    private let descriptor: Int32
    private let reply: Reply

    init(_ reply: Reply) throws {
        folder = URL(fileURLWithPath: "/tmp/jerd-fpm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        socket = folder.appendingPathComponent("php.sock")
        self.reply = reply
        descriptor = try Self.listen(at: socket)
        let thread = Thread { [self] in acceptLoop() }
        thread.start()
    }

    /// Closes the listener and removes the folder.
    func stop() {
        shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
        try? FileManager.default.removeItem(at: folder)
    }

    private func acceptLoop() {
        while true {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            switch reply {
            case .bytes(let data):
                var buffer = [UInt8](repeating: 0, count: 4_096)
                _ = read(client, &buffer, buffer.count)
                _ = DescriptorIO.writeAll(data, to: client)
                close(client)
            case .silent:
                continue
            case .close:
                close(client)
            }
        }
    }

    static func listen(at socket: URL) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(socket.path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard descriptor >= 0, bound == 0, Darwin.listen(descriptor, 8) == 0 else {
            throw JerdError.unavailable("Cannot create a test socket.")
        }
        return descriptor
    }

    /// A complete ping response: STDOUT with headers and body, then END_REQUEST.
    static func response(body: String = "Jerd FPM is ready.", appStatus: UInt8 = 0) -> Data {
        let output = Data("Content-type: text/plain;charset=UTF-8\r\n\r\n\(body)".utf8)
        return record(6, output) + record(6, Data()) + record(3, Data([0, 0, 0, appStatus, 0, 0, 0, 0]))
    }

    /// One FastCGI record with request ID 1 and optional padding.
    static func record(
        _ type: UInt8, _ content: Data, version: UInt8 = 1, requestID: UInt8 = 1, padding: UInt8 = 0
    )
        -> Data
    {
        Data([version, type, 0, requestID, UInt8(content.count >> 8), UInt8(content.count & 0xFF), padding, 0])
            + content + Data(repeating: 0, count: Int(padding))
    }
}
