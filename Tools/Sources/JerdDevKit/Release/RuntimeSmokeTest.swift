import Foundation
import JerdManifest
import JerdRuntimes

/// Runs each executable of the signed payloads inside the candidate app once, with a version or module
/// list argument. The payloads have new signatures, the hardened runtime, and reviewed entitlements, so
/// a fault that only the signed form has (library validation, a missing entitlement) stops the release
/// before anything is public. The commands use a private temporary home and a minimal environment,
/// and none of them opens a network connection. RustFS installs on demand, so the prepared RustFS
/// runs once beside the signed XZ library of the app (`runSupportCheck`).
struct RuntimeSmokeTest: Sendable {
    /// One command line.
    struct Command: Equatable, Sendable {
        var executable: URL
        var arguments: [String]
    }

    let shell: ReleaseShell
    let layout: CandidateLayout

    func run() async throws {
        let commands = try Self.commands(PayloadSigner.verifiedPayloads(in: layout.appPayloads))
        let home = try FileTree.makeTemporaryFolder(prefix: "jerd-release-smoke")
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path, "TMPDIR": home.path, "PATH": "/usr/bin:/bin", "LANG": "C"]
        for command in commands {
            try await shell.run(
                command.executable, command.arguments, limit: TimeLimit.probe, log: layout.log("runtime-smoke"),
                environment: environment, directory: home)
        }
        shell.console.success("\(commands.count) commands of the signed runtimes ran.")
        try await runSupportCheck(home: home, environment: environment)
    }

    /// The commands of each payload, in catalog order. Composer and the Laravel installer are PHP
    /// programs, so they run with the embedded PHP.
    static func commands(_ payloads: [BundledPayload]) throws -> [Command] {
        let php = payloads.first { $0.receipt.kind == .php }.map { $0.receipt.executable.url(in: $0.origin) }
        return try payloads.flatMap { payload -> [Command] in
            let receipt = payload.receipt
            let main = receipt.executable.url(in: payload.origin)
            switch receipt.kind {
            case .php:
                let fpm = receipt.secondaryExecutable.map {
                    [Command(executable: $0.url(in: payload.origin), arguments: ["-v"])]
                }
                return [Command(executable: main, arguments: ["-v"]), Command(executable: main, arguments: ["-m"])]
                    + (fpm ?? [])
            case .composer, .laravel:
                guard let php else {
                    throw DevFailure.checkFailed(
                        "\(receipt.id) needs the embedded PHP, which the app does not contain.")
                }
                let extra = receipt.kind == .composer ? ["--no-interaction"] : []
                return [Command(executable: php, arguments: [main.path, "--version"] + extra)]
            case .caddy, .mailpit:
                return [Command(executable: main, arguments: ["version"])]
            case .mysql, .postgresql, .redis, .rustfs, .cloudflared:
                return [Command(executable: main, arguments: ["--version"])]
            }
        }
    }
}
