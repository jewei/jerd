import Foundation
import Testing

/// The signed XPC check. It needs a code-signing identity of an Apple team, so it runs only with
/// `JERD_XPC_IDENTITY` set, for example `JERD_XPC_IDENTITY="Apple Development: Name (TEAMID)"`.
/// It signs a copy of the `JerdXPCCheck` executable as `dev.jerd.app` and runs its three modes.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["JERD_XPC_IDENTITY"] != nil))
struct SignedXPCCheckTests {
    private func run(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    /// The built check, signed as the app. `swift test` builds it beside the test bundle.
    private func signedCheck(in folder: URL) throws -> URL {
        var products = Bundle.module.bundleURL
        while products.pathComponents.count > 1,
            !FileManager.default.fileExists(atPath: products.appendingPathComponent("JerdXPCCheck").path)
        {
            products.deleteLastPathComponent()
        }
        let check = folder.appendingPathComponent("JerdXPCCheck")
        try FileManager.default.copyItem(at: products.appendingPathComponent("JerdXPCCheck"), to: check)
        let identity = try #require(ProcessInfo.processInfo.environment["JERD_XPC_IDENTITY"])
        let signing = try run(
            URL(fileURLWithPath: "/usr/bin/codesign"),
            ["--force", "--sign", identity, "--identifier", "dev.jerd.app", "--options", "runtime", check.path])
        #expect(signing.status == 0, "codesign failed: \(signing.output)")
        return check
    }

    @Test func signedXPCAcceptsTheAppAndRefusesWrongIdentities() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-xpc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let check = try signedCheck(in: folder)
        let allow = try run(check, ["allow"])
        #expect(
            allow.status == 0 && allow.output.hasPrefix("PASS: signed XPC transferred both loopback sockets"),
            "\(allow.output)")
        for mode in ["reject-client", "reject-server"] {
            let result = try run(check, [mode])
            #expect(
                result.status == 0 && result.output.hasPrefix("PASS: XPC rejected the incorrect \(mode)"),
                "\(result.output)")
        }
    }
}
