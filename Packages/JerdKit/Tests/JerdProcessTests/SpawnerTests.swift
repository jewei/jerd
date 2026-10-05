import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct SpawnerTests {
    private func inspect(in folder: URL, listeners: InheritedListeners? = nil) async throws -> [String: String] {
        let executable = try await Fixtures.shared.executable("spawn-inspector")
        let request = ProcessRequest(executable: executable, workingDirectory: folder, listeners: listeners)
        let result = try await CommandRunner().run(request, timeout: .seconds(10))
        #expect(result.status == 0)
        var report: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { report[parts[0]] = parts[1] }
        }
        return report
    }

    @Test func aChildGetsOnlyStandardDescriptorsACleanSignalStateAndItsOwnGroup() async throws {
        let folder = try TemporaryDirectory(" spawn café")
        defer { folder.remove() }
        let leaked = open("/dev/null", O_RDONLY)  // Deliberately without O_CLOEXEC.
        defer { close(leaked) }
        let previous = signal(SIGUSR2, SIG_IGN)
        defer { signal(SIGUSR2, previous) }
        let report = try await inspect(in: folder.url)
        #expect(report["descriptors"] == "0 1 2")
        #expect(report["blocked"] == "0")
        #expect(report["ignored"] == "0")
        #expect(report["group-leader"] == "yes")
        #expect(report["stdin-null"] == "yes")
        #expect(report["cwd"] == realPath(folder.url))
    }

    @Test func listenersArriveAsDescriptorsThreeAndFour() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let http = try LoopbackListener()
        let https = try LoopbackListener()
        let report = try await inspect(
            in: folder.url, listeners: InheritedListeners(http: http.handle, https: https.handle))
        #expect(report["descriptors"] == "0 1 2 3 4")
        #expect(report["listener-3"] == String(http.port))
        #expect(report["listener-4"] == String(https.port))
    }

    @Test func aListenerThatIsNotALoopbackTCPSocketIsRefused() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let http = try LoopbackListener()
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/true"), workingDirectory: folder.url,
            listeners: InheritedListeners(http: http.handle, https: FileHandle.nullDevice))
        await #expect(throws: JerdError.invalid("Expected a bound IPv4 loopback TCP socket.")) {
            try await CommandRunner().run(request, timeout: .seconds(5))
        }
    }

    @Test func theEnvironmentIsExactlyThePlan() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/env"), workingDirectory: folder.url, environment: ["EXTRA": "1"])
        let result = try await CommandRunner().run(request, timeout: .seconds(5))
        #expect(
            result.output == "EXTRA=1\nHOME=\(folder.url.path)\nLANG=en_US.UTF-8\nPATH=/usr/bin:/bin:/usr/sbin:/sbin\n")
    }
}

/// The canonical path of an existing item, as `getcwd` reports it (with `/private`).
private func realPath(_ url: URL) -> String? {
    guard let resolved = realpath(url.path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}
