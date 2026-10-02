import Foundation
import Darwin

public protocol FPMProbing: Sendable {
    func check(socket: URL) async throws
}

/// A bounded FastCGI request to FPM's built-in ping handler. It executes no project file.
public struct FPMProbe: FPMProbing {
    private let timeout: Duration
    public init(timeout: Duration = .seconds(3)) { self.timeout = timeout }

    public func check(socket: URL) async throws {
        let task = Task.detached { try exchange(socket: socket) }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func exchange(socket path: URL) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JerdError.process("Cannot create the FPM probe socket.") }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw JerdError.process("Cannot configure the FPM probe socket.") }
        var address = sockaddr_un()
        let bytes = Array(path.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path), !bytes.contains(0) else { throw JerdError.invalid("The FPM probe path is invalid.") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes + [0]) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        let deadline = ContinuousClock.now + timeout
        guard connected == 0 || errno == EINPROGRESS else { throw JerdError.process("FPM did not accept its readiness request.") }
        if connected != 0 {
            try wait(descriptor, for: Int16(POLLOUT), until: deadline)
            var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                throw JerdError.process("FPM did not accept its readiness request.")
            }
        }
        var parameters = Data()
        for (key, value) in [("REQUEST_METHOD", "GET"), ("SCRIPT_NAME", ConfigurationGenerator.fpmHealthPath),
                             ("SCRIPT_FILENAME", ConfigurationGenerator.fpmHealthPath), ("REQUEST_URI", ConfigurationGenerator.fpmHealthPath),
                             ("SERVER_PROTOCOL", "HTTP/1.1"), ("GATEWAY_INTERFACE", "CGI/1.1")] {
            parameters.append(contentsOf: [UInt8(key.utf8.count), UInt8(value.utf8.count)])
            parameters.append(contentsOf: key.utf8); parameters.append(contentsOf: value.utf8)
        }
        let request = record(type: 1, content: Data([0, 1, 0, 0, 0, 0, 0, 0])) + record(type: 4, content: parameters)
            + record(type: 4, content: Data()) + record(type: 5, content: Data())
        var sent = 0
        while sent < request.count {
            try wait(descriptor, for: Int16(POLLOUT), until: deadline)
            let count = request.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!.advanced(by: sent), request.count - sent) }
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else { throw JerdError.process("Cannot send the FPM readiness request.") }
            sent += count
        }
        var output = Data(), received = 0
        while received <= 16_384 {
            let header = try read(descriptor, count: 8, until: deadline)
            guard header[0] == 1, header[2] == 0, header[3] == 1 else { throw JerdError.process("FPM returned an invalid FastCGI response.") }
            let length = Int(header[4]) * 256 + Int(header[5]), padding = Int(header[6])
            received += 8 + length + padding
            guard received <= 16_384 else { throw JerdError.process("The FPM readiness response is too large.") }
            let body = try read(descriptor, count: length + padding, until: deadline).prefix(length)
            if header[1] == 6 { output.append(body) }
            if header[1] == 3 {
                guard body.count == 8, body.prefix(5).allSatisfy({ $0 == 0 }),
                      let response = String(data: output, encoding: .utf8),
                      response.components(separatedBy: "\r\n\r\n").last == ConfigurationGenerator.fpmHealthResponse else {
                    throw JerdError.process("FPM did not return its readiness response.")
                }
                return
            }
        }
        throw JerdError.process("The FPM readiness response is too large.")
    }

    private func record(type: UInt8, content: Data) -> Data {
        Data([1, type, 0, 1, UInt8(content.count >> 8), UInt8(content.count & 255), 0, 0]) + content
    }
    private func read(_ descriptor: Int32, count: Int, until deadline: ContinuousClock.Instant) throws -> Data {
        var data = Data(), buffer = [UInt8](repeating: 0, count: max(count, 1))
        while data.count < count {
            try wait(descriptor, for: Int16(POLLIN), until: deadline)
            let read = Darwin.read(descriptor, &buffer, count - data.count)
            if read < 0, errno == EINTR || errno == EAGAIN { continue }
            guard read > 0 else { throw JerdError.process("FPM closed its readiness connection without a complete response.") }
            data.append(contentsOf: buffer.prefix(read))
        }
        return data
    }
    private func wait(_ descriptor: Int32, for event: Int16, until deadline: ContinuousClock.Instant) throws {
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            var item = pollfd(fd: descriptor, events: event, revents: 0)
            let result = poll(&item, 1, 50)
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw JerdError.process("The FPM readiness connection failed.") }
            if result > 0 { return }
        }
        throw JerdError.process("FPM did not answer its readiness request in time.")
    }
}
