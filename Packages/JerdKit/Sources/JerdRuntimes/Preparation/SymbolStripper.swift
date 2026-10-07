import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess

/// Strips the executables that `SymbolStripping` names, after the preparer and before the version
/// probe, so the probe runs the stripped files and the receipt records them.
package struct SymbolStripper: Sendable {
    package let context: PreparationContext
    package let requirement: SymbolStripping.Requirement

    package init(context: PreparationContext, requirement: SymbolStripping.Requirement) {
        self.context = context
        self.requirement = requirement
    }

    package func strip() async throws {
        let kind = context.release.kind
        let files = try SymbolStripping.executables(for: kind, version: context.release.version)
        guard !files.isEmpty, try await developerToolsAllowStripping() else { return }
        try RuntimePreparers.requireFiles(files.map(\.string), in: context.payload, kind: kind)
        for file in files {
            let path = file.url(in: context.payload).path
            try await context.run(
                SymbolStripping.strip.path, SymbolStripping.arguments + [path], in: context.staging,
                timeout: SymbolStripping.timeout)
            let check = try await command(SymbolStripping.codesign, ["--verify", "--strict", path])
            guard check.succeeded else { throw SymbolStripping.brokenSignature(file, kind: kind) }
        }
    }

    /// True when the requirement is `.required`, or when this Mac has a developer folder.
    private func developerToolsAllowStripping() async throws -> Bool {
        guard requirement == .whenDeveloperToolsExist else { return true }
        let result = try await command(SymbolStripping.xcodeSelect, ["-p"])
        let folder = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, folder.hasPrefix("/") else { return false }
        return FileProbe.presence(at: URL(fileURLWithPath: folder)) == .present
    }

    private func command(_ executable: URL, _ arguments: [String]) async throws -> CommandResult {
        try await context.commands.run(
            ProcessRequest(executable: executable, arguments: arguments, workingDirectory: context.staging),
            timeout: SymbolStripping.timeout)
    }
}
