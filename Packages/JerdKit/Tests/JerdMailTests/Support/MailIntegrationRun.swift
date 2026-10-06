import Darwin
import Foundation
import JerdFoundation
import JerdMail
import JerdProcess
import JerdServiceKit
import Testing

/// A real mail manager on a prepared Mailpit runtime, in a temporary data folder, on free
/// loopback ports.
struct MailIntegrationRun {
    let directory: TemporaryDirectory
    let layout: DataLayout
    let manager: MailManager
    let runtime: MailRuntime

    init(runtime folder: URL) async throws {
        directory = try TemporaryDirectory(" mail persistence café")
        layout = DataLayout(root: directory.path("Jerd"))
        manager = MailManager(layout: layout, effects: ServiceEffects(processes: ProcessSupervisor()))
        runtime = MailRuntime(id: "mailpit-1.31.3-arm64", version: "1.31.3", path: folder.path)
        _ = try await manager.load()
        try await manager.registerRuntime(runtime)
        try await manager.edit(ports: try Self.freePorts())
    }

    var mail: MailLayout { layout.mail }

    func ports() async -> MailPorts { await manager.snapshot().settings.ports }

    /// `curl` against the inbox web service, with extra arguments before the URL.
    func get(_ path: String, _ arguments: [String] = []) async throws -> CommandResult {
        let url = "http://127.0.0.1:\(await ports().web)/\(path)"
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: ["--silent", "--show-error", "--max-time", "3", "--noproxy", "*"] + arguments + [url],
            workingDirectory: directory.url)
        return try await CommandRunner().run(request, timeout: .seconds(5))
    }

    /// The JSON object at `path`.
    func object(_ path: String) async throws -> [String: Any] {
        let result = try await get(path)
        #expect(result.succeeded, "\(result.output)")
        return try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
    }

    /// Sends `message` through the local SMTP service, as an application does.
    func send(_ message: String, from sender: String = "hello@jerd.test", to recipients: [String]) async throws {
        let file = directory.path("message-\(UUID().uuidString).eml")
        try AtomicFile.write(Data(message.utf8), to: file)
        let arguments =
            ["--silent", "--show-error", "--max-time", "5", "--noproxy", "*"]
            + ["--url", "smtp://127.0.0.1:\(await ports().smtp)", "--mail-from", sender]
            + recipients.flatMap { ["--mail-rcpt", $0] } + ["--upload-file", file.path]
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/curl"), arguments: arguments, workingDirectory: directory.url)
        let result = try await CommandRunner().run(request, timeout: .seconds(7))
        #expect(result.succeeded, "\(result.output)")
    }

    /// Two different free loopback ports above 1023, from the kernel.
    static func freePorts() throws -> MailPorts {
        let first = try freePort()
        var second = try freePort()
        while second == first { second = try freePort() }
        return MailPorts(smtp: first, web: second)
    }

    static func freePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
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
        guard descriptor >= 0, bound else { throw JerdError.unavailable("Cannot find a free test port.") }
        return UInt16(bigEndian: address.sin_port)
    }
}
