import Foundation
import JerdFoundation
import os

@testable import JerdCLICore

/// A CA bundle preparer with a fixed answer that counts its calls.
final class FakeCABundles: CLICABundlePreparing {
    private let answer: Result<URL?, JerdError>
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(_ answer: Result<URL?, JerdError>) {
        self.answer = answer
    }

    var callCount: Int { calls.withLock { $0 } }

    func prepareForCLI(layout: DataLayout) throws -> URL? {
        calls.withLock { $0 += 1 }
        return try answer.get()
    }
}

/// Records the plan instead of replacing the test process, and reports `errno`.
final class RecordingProcessImage: ProcessImageReplacing {
    private let plans = OSAllocatedUnfairLock<[CLILaunchPlan]>(initialState: [])
    private let failure: Int32

    init(failure: Int32 = ENOENT) {
        self.failure = failure
    }

    var recorded: [CLILaunchPlan] { plans.withLock { $0 } }

    func replace(with plan: CLILaunchPlan) -> Int32 {
        plans.withLock { $0.append(plan) }
        return failure
    }
}

/// Records diagnostic lines.
final class RecordingDiagnostics: DiagnosticWriting {
    private let lines = OSAllocatedUnfairLock<[String]>(initialState: [])

    var recorded: [String] { lines.withLock { $0 } }

    func writeLine(_ line: String) {
        lines.withLock { $0.append(line) }
    }
}

/// A signature check that accepts every file, or refuses with a fixed error, and can run an
/// action on each call (for example, a concurrent edit of a shell file).
final class FakeSignatureCheck: LauncherSignatureChecking {
    private let refusal: JerdError?
    private let action: @Sendable (Int) -> Void
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(refusal: JerdError? = nil, action: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.refusal = refusal
        self.action = action
    }

    var callCount: Int { calls.withLock { $0 } }

    func checkSignature(of file: URL) throws {
        let call = calls.withLock { count in
            count += 1
            return count
        }
        action(call)
        if let refusal { throw refusal }
    }
}
