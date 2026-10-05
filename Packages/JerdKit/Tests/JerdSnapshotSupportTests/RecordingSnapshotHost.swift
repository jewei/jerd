@testable import JerdSnapshotSupport

/// Records what `SnapshotCommand` asks of its process, and never changes the test process.
@MainActor
final class RecordingSnapshotHost: SnapshotHosting {
    var preparedContrast: [SnapshotContrast] = []
    var contrastPassArguments: [[String]] = []
    var contrastPassStatus: Int32 = 0
    var output: [String] = []
    var errors: [String] = []

    func prepareProcess(contrast: SnapshotContrast) {
        preparedContrast.append(contrast)
    }

    func runContrastPass(arguments: [String]) -> Int32 {
        contrastPassArguments.append(arguments)
        return contrastPassStatus
    }

    func write(_ line: String) {
        output.append(line)
    }

    func writeError(_ line: String) {
        errors.append(line)
    }
}
