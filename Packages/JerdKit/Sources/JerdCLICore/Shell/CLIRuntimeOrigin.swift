import Foundation
import JerdFoundation

/// Where a PHP runtime that a command can select comes from. The origin decides its trust.
///
/// The one rule:
/// - `managed`: the executable is below `runtimes/` or `runtime-updates/`. Jerd installed it with
///   a receipt, so the shell setup verifies it against that receipt and stops when it fails.
/// - `imported`: the executable is anywhere else. The user chose it explicitly ("Select PHP CLI
///   and FPM…"), so it is trusted and never blocks the setup.
///
/// The launcher does not hash a runtime on each call (cost). It checks only that the selected
/// executable is a regular file that the user can run.
enum CLIRuntimeOrigin: Equatable, Sendable {
    case managed
    case imported

    /// The origin of `executable`, after symbolic link resolution, as `ManagedExecutableVerifier`
    /// resolves it.
    init(executable: URL, layout: DataLayout) {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let roots = [layout.runtimes.developmentRuntimesDirectory, layout.runtimes.managedRuntimesDirectory]
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.pathComponents }
        self = roots.contains { resolved.count > $0.count && resolved.starts(with: $0) } ? .managed : .imported
    }
}
