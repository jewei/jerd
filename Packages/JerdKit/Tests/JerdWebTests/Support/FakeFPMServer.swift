import Darwin
import Foundation
import JerdFoundation
import os

/// A Unix socket server that answers each connection with fixed bytes, or stays silent.
///
/// The socket lives in a short folder below `/tmp`, because a socket path must stay below 104 bytes.
final class FakeFPMServer: @unchecked Sendable {
    // Safety: `folder`, `socket`, `descriptor`, and `reply` are set once in init. The accept thread
    // owns the listener and the kept clients; other threads touch only `state` and `finished`.
    enum Reply {
        /// Read the request, then write these bytes and close.
        case bytes(Data)
        /// Accept and keep the connection open without an answer.
        case silent
        /// Read the request, then close without an answer.
        case close
    }

    private struct State {
        var accepted = 0
        var stopping = false
    }

    let folder: URL
    let socket: URL
    private let descriptor: Int32
    private let reply: Reply
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let finished = DispatchSemaphore(value: 0)

    init(_ reply: Reply) throws {
        folder = URL(fileURLWithPath: "/tmp/jerd-fpm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        socket = folder.appendingPathComponent("php.sock")
        self.reply = reply
        descriptor = try Self.listen(at: socket)
        let thread = Thread { [self] in acceptLoop() }
        thread.start()
    }

    /// The number of connections that the server has accepted.
    var accepted: Int { state.withLock { $0.accepted } }

    /// Stops the accept thread, waits until it has closed every descriptor, and removes the folder.
    ///
    /// Only the accept thread closes the listener, so it never calls `accept` on a descriptor
    /// number that another server in the same test process now uses.
    func stop() {
        state.withLock { $0.stopping = true }
        finished.wait()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Polls in short slices, because `shutdown` does not wake `accept` on a Darwin listener.
    private func acceptLoop() {
        var kept: [Int32] = []
        defer {
            kept.forEach { close($0) }
            close(descriptor)
            finished.signal()
        }
        while !state.withLock({ $0.stopping }) {
            var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&entry, 1, 20) > 0 else { continue }
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { continue }
            state.withLock { $0.accepted += 1 }
            if case .silent = reply { kept.append(client) } else { answer(client) }
        }
    }

    private func answer(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        _ = read(client, &buffer, buffer.count)
        if case .bytes(let data) = reply { _ = DescriptorIO.writeAll(data, to: client) }
        close(client)
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
        // A full backlog refuses a Darwin Unix connect at once, so keep room for every test ping.
        guard descriptor >= 0, bound == 0, Darwin.listen(descriptor, SOMAXCONN) == 0 else {
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
