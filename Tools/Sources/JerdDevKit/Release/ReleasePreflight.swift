import Foundation
import JerdManifest

/// Checks the credentials and the payloads before the long build, so a missing key fails in seconds.
/// The private keys stay in the Keychain: the checks only ask the tools that use them.
struct ReleasePreflight: Sendable {
    let shell: ReleaseShell
    let inputs: ReleaseInputs

    func run() async throws {
        try await Self.checkSparkleKey(shell)
        try await shell.xcrun(
            ["notarytool", "history"] + inputs.notary.arguments + ["--output-format", "json"],
            limit: TimeLimit.gitHub)
        let identities = try await shell.output(
            SystemProgram.security, ["find-identity", "-v", "-p", "codesigning"], limit: TimeLimit.probe)
        guard identities.contains("\"\(inputs.signing.identity)\"") else {
            throw DevFailure.missingPrerequisite(
                "The Keychain has no valid code-signing identity \"\(inputs.signing.identity)\".")
        }
        try checkPayloads()
        shell.console.success("The Sparkle key, the notary profile, the signing identity, and the payloads are ready.")
    }

    /// The Sparkle private key in the Keychain belongs to the public key of every installed app.
    static func checkSparkleKey(_ shell: ReleaseShell) async throws {
        let tool = try shell.sparkleTool("generate_keys")
        let key = try await shell.output(
            tool, ["--account", ReleaseNames.sparkleAccount, "-p"], limit: TimeLimit.probe)
        guard key == AppUpdateSettings.officialPublicKey else {
            throw DevFailure.checkFailed(
                "The Keychain account \(ReleaseNames.sparkleAccount) does not hold the key of the app's Sparkle public key."
            )
        }
    }

    /// Every pinned payload is prepared and matches its receipt, because the archive embeds them.
    func checkPayloads() throws {
        let repository = shell.repository
        let catalog = try PayloadInventory.catalog(at: repository.runtimeCatalog)
        let entries = PayloadInventory(root: repository.payloads, catalog: catalog).entries()
        let problems = entries.compactMap { entry -> String? in
            switch entry.state {
            case .valid: nil
            case .missing: "\(entry.pin.id) is not prepared"
            case .invalid(let message): "\(entry.pin.id): \(message)"
            }
        }
        guard problems.isEmpty else {
            throw DevFailure.missingPrerequisite(
                "A release needs every runtime payload. \(problems.joined(separator: "; ")). Run ./dev runtimes prepare."
            )
        }
    }
}
