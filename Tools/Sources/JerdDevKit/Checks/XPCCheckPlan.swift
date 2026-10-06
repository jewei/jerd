import Foundation

/// Plans and judges `./dev check xpc`. The check itself is the opt-in JerdKit test `SignedXPCCheckTests`,
/// which runs only when `JERD_XPC_IDENTITY` names a code-signing identity. It signs the `JerdXPCCheck` probe
/// as the app and proves that signed XPC transfers the listener sockets only between the
/// right code identities.
enum XPCCheckPlan {
    /// The test filter. The JerdKit test of the signed XPC check has this name.
    static let testFilter = "SignedXPCCheckTests"
    static let identityVariable = "JERD_XPC_IDENTITY"

    /// `swift test` of only the XPC check. Inherited `JERD_*` values are removed, as in `./dev test`.
    static func invocation(
        repository: Repository, toolchain: Toolchain, identity: String, inherited: [String: String]
    ) -> Invocation {
        var environment = inherited.filter { !$0.key.hasPrefix(TestEnvironment.prefix) }
        environment[identityVariable] = identity
        return Invocation(
            executable: toolchain.xcrun,
            arguments: ["swift", "test", "--package-path", repository.kitPackage.path, "--filter", testFilter],
            environment: environment, workingDirectory: repository.root, timeout: TimeLimit.test)
    }

    /// One result per test that the output names, and the reason why the check did not pass, if any.
    /// A run without any test, or with a skipped test, does not prove anything, so it fails.
    static func evaluate(_ result: InvocationResult) -> (cases: [EvidenceRecord.CaseResult], failure: String?) {
        let output = result.standardOutput + "\n" + result.standardError
        let cases = output.split(separator: "\n").compactMap { caseResult(String($0)) }
        if output.contains("No matching test cases were run") || cases.isEmpty {
            return (cases, "No \(testFilter) test ran. The JerdKit package must contain the signed XPC check.")
        }
        if cases.contains(where: { $0.detail == "skipped" }) {
            return (cases, "The \(testFilter) test was skipped. It must run with \(identityVariable).")
        }
        guard result.succeeded else { return (cases, "The \(testFilter) test \(result.failureSummary).") }
        return (cases, nil)
    }

    /// Parses a Swift Testing result line such as `✔ Test "name" passed after 0.1 seconds.`.
    static func caseResult(_ line: String) -> EvidenceRecord.CaseResult? {
        let markers: [(prefix: String, word: String)] = [
            ("✔ Test ", "passed"), ("✘ Test ", "failed"), ("➜ Test ", "skipped"),
        ]
        for marker in markers where line.hasPrefix(marker.prefix) && !line.hasPrefix(marker.prefix + "run with") {
            let rest = line.dropFirst(marker.prefix.count)
            guard let end = rest.range(of: " \(marker.word)") else { continue }
            return EvidenceRecord.CaseResult(
                name: String(rest[..<end.lowerBound]), passed: marker.word == "passed", detail: marker.word)
        }
        return nil
    }
}
