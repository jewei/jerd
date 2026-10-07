import Foundation
import JerdRuntimes

/// Checks that every Mach-O file of a prepared payload loads only macOS system libraries and files
/// of its own payload: each `@loader_path`, `@rpath`, and `@executable_path` reference resolves. It
/// covers the embedded and the on-demand payloads, so a new pin cannot add a broken reference
/// without notice. The app never rewrites load commands of a signed upstream file.
struct PayloadDependencyCheck: Sendable {
    let context: DevContext

    /// One line for each reference that does not resolve, as `<file>: <reason>`. Empty when all resolve.
    func problems(in payload: BundledPayload) async throws -> [String] {
        let resolver = DependencyResolver(payload: payload.origin)
        var problems: [String] = []
        for path in payload.receipt.fileRecords.keys.sorted() {
            let file = path.url(in: payload.origin)
            guard MachOFile.isMachO(file) else { continue }
            let invocation = Invocation(
                executable: SystemProgram.otool, arguments: ["-arch", "arm64", "-l", file.path],
                timeout: TimeLimit.probe)
            let result = try await context.run(invocation, output: .capture)
            guard result.succeeded else {
                problems.append("\(path.string): otool cannot read the load commands.")
                continue
            }
            let info = MachOLoadInfo.parse(result.standardOutput)
            for dependency in info.dependencies {
                do {
                    _ = try resolver.resolve(dependency, of: file, rpaths: info.rpaths)
                } catch let failure as DevFailure {
                    problems.append("\(path.string): \(failure.message)")
                }
            }
        }
        return problems
    }
}
