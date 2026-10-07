import Foundation
import JerdRuntimes

/// Checks the load commands of every Mach-O file of a prepared payload, from one `otool` run each.
///
/// Each file loads only macOS system libraries and files of its own payload: each `@loader_path`,
/// `@rpath`, and `@executable_path` reference resolves. It covers the embedded and the on-demand
/// payloads, so a new pin cannot add a broken reference without notice. The app never rewrites load
/// commands of a signed upstream file.
///
/// A file of an embedded payload also runs on the minimum macOS of the app. A source build that
/// targets the macOS of the build Mac fails here, before a release refuses it. An on-demand payload
/// is exempt: the app checks the minimum of its release on the user's Mac before it installs it.
struct PayloadDependencyCheck: Sendable {
    let context: DevContext

    /// One line for each problem, as `<file>: <reason>`. Empty when all references resolve.
    /// - Parameter minimumMacOS: The minimum that each file must run on, or nil for no check.
    func problems(in payload: BundledPayload, minimumMacOS: MinimumMacOS?) async throws -> [String] {
        try await problems(
            files: payload.receipt.fileRecords.keys.map(\.string), in: payload.origin, minimumMacOS: minimumMacOS)
    }

    /// The same check for the recorded files of any folder, for example the XZ support library.
    func problems(files: [String], in folder: URL, minimumMacOS: MinimumMacOS?) async throws -> [String] {
        let resolver = DependencyResolver(payload: folder)
        var problems: [String] = []
        for path in files.sorted() {
            let file = folder.appending(path: path)
            guard MachOFile.isMachO(file) else { continue }
            let invocation = Invocation(
                executable: SystemProgram.otool, arguments: ["-arch", "arm64", "-l", file.path],
                timeout: TimeLimit.probe)
            let result = try await context.run(invocation, output: .capture)
            guard result.succeeded else {
                problems.append("\(path): otool cannot read the load commands.")
                continue
            }
            let info = MachOLoadInfo.parse(result.standardOutput)
            if let minimumMacOS, let problem = Self.minimumProblem(info, minimumMacOS: minimumMacOS) {
                problems.append("\(path): \(problem)")
            }
            for dependency in info.dependencies {
                do {
                    _ = try resolver.resolve(dependency, of: file, rpaths: info.rpaths)
                } catch let failure as DevFailure {
                    problems.append("\(path): \(failure.message)")
                }
            }
        }
        return problems
    }

    /// The reason when the file needs a newer macOS than `minimumMacOS`, or nil.
    static func minimumProblem(_ info: MachOLoadInfo, minimumMacOS: MinimumMacOS) -> String? {
        guard let required = MinimumMacOS(info.minimumSystem) else {
            return "otool shows an invalid minimum macOS \(info.minimumSystem)."
        }
        guard required > minimumMacOS else { return nil }
        return "it needs macOS \(required), above the deployment target \(minimumMacOS) of the app "
            + "(MACOSX_DEPLOYMENT_TARGET in Configuration/Base.xcconfig)."
    }
}
