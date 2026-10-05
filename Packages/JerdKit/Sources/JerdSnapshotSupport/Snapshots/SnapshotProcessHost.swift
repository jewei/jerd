import AppKit

/// The live `SnapshotHosting` of the `jerd-snapshots` process.
@MainActor
package struct SnapshotProcessHost: SnapshotHosting {
    package init() {}

    package func prepareProcess(contrast: SnapshotContrast) {
        SnapshotProcessSettings.apply(contrast: contrast)
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    /// Starts this executable by its absolute path with an argument array, and waits for it.
    package func runContrastPass(arguments: [String]) -> Int32 {
        guard let executable = Bundle.main.executableURL else {
            writeError("The path of jerd-snapshots is not known, so the contrast pass cannot start.")
            return SnapshotExitStatus.failure.rawValue
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            writeError("The contrast pass could not start: \(error.localizedDescription)")
            return SnapshotExitStatus.failure.rawValue
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    package func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    package func writeError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
