import Foundation

/// Plans `swift test` runs for the JerdKit package and the Tools package.
enum TestPlan {
    /// Normalizes and checks target names. `JerdWeb` and `JerdWebTests` both select `JerdWebTests`.
    /// - Parameter available: Names of the test targets, for example `JerdWebTests`.
    static func testTargets(for requested: [String], available: [String]) throws -> [String] {
        var result: [String] = []
        for name in requested {
            let target = name.hasSuffix("Tests") ? name : name + "Tests"
            guard available.contains(target) else {
                let valid = available.sorted().map { String($0.dropLast("Tests".count)) }.joined(separator: ", ")
                throw DevFailure.usage("Unknown test target \"\(name)\". Use one of: \(valid).")
            }
            if !result.contains(target) { result.append(target) }
        }
        return result
    }

    /// `--filter` arguments. Each target gets one filter; a user filter narrows every target filter.
    /// Without targets the user filter applies to the whole package.
    static func filterArguments(testTargets: [String], filter: String?) -> [String] {
        guard !testTargets.isEmpty else {
            return filter.map { ["--filter", $0] } ?? []
        }
        return testTargets.flatMap { target -> [String] in
            let pattern = filter.map { "^\(target)\\..*(?:\($0))" } ?? "^\(target)\\."
            return ["--filter", pattern]
        }
    }

    static func kitTests(
        repository: Repository,
        toolchain: Toolchain,
        testTargets: [String],
        filter: String?,
        environment: [String: String]
    ) -> Invocation {
        swiftTest(
            package: repository.kitPackage, toolchain: toolchain,
            filters: filterArguments(testTargets: testTargets, filter: filter), environment: environment)
    }

    static func toolTests(
        repository: Repository,
        toolchain: Toolchain,
        filter: String?,
        environment: [String: String]
    ) -> Invocation {
        swiftTest(
            package: repository.toolsPackage, toolchain: toolchain,
            filters: filterArguments(testTargets: [], filter: filter), environment: environment)
    }

    /// Without `--verbose`, a test run shows failures, diagnostics, and the final count. It hides build
    /// progress, "started" events, and one line for each passed test or suite.
    static func showsInQuietMode(_ line: String) -> Bool {
        let hiddenPrefixes = ["◇ ", "↳ ", "✔ Suite ", "\t Executed "]
        if SwiftPMOutput.isProgress(line) || hiddenPrefixes.contains(where: line.hasPrefix) {
            return false
        }
        // XCTest also reports its empty run. Keep only its failures.
        if line.hasPrefix("Test Suite '") || line.hasPrefix("Test Case '") {
            return line.contains(" failed")
        }
        return !line.hasPrefix("✔ Test ") || line.hasPrefix("✔ Test run ")
    }

    private static func swiftTest(
        package: URL,
        toolchain: Toolchain,
        filters: [String],
        environment: [String: String]
    ) -> Invocation {
        Invocation(
            executable: toolchain.xcrun,
            arguments: ["swift", "test", "--package-path", package.path] + filters,
            environment: environment,
            workingDirectory: package,
            timeout: TimeLimit.test)
    }
}
