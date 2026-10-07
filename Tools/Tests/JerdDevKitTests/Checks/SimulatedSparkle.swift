import Foundation

@testable import JerdDevKit

/// Answers the commands of `./dev check updates` as the real tools would, without Sparkle. The launch
/// of version 1 writes the events of its case, replaces the installed app when the case installs,
/// leaves version 2 running for a few checks, and writes a Sparkle cache folder.
struct SimulatedSparkle: Sendable {
    let inspector: FakeProcessInspector
    let home: URL
    /// Event lines that replace the normal events of a case.
    var overrides: [UpdateCase: [String]] = [:]

    var runner: RecordingProcessRunner {
        RecordingProcessRunner { invocation in try answer(invocation) }
    }

    func answer(_ invocation: Invocation) throws -> InvocationResult {
        let arguments = invocation.arguments
        var output = ""
        switch invocation.executable.lastPathComponent {
        case "xcrun" where arguments.first == "swiftc":
            try Data("binary".utf8).write(to: URL(filePath: arguments[arguments.count - 1]))
        case "UpdaterTest" where arguments.first == "generate-test-key":
            output = Data(repeating: 7, count: 32).base64EncodedString() + "\n"
        case "UpdaterTest":
            try launch(invocation.executable)
        case "ditto" where arguments.first == "-c":
            try Data(repeating: 1, count: 512).write(to: URL(filePath: arguments[arguments.count - 1]))
        case "codesign" where arguments.first == "-d":
            let name = URL(filePath: arguments[arguments.count - 1]).lastPathComponent
            let identifier = name == "Autoupdate" ? "Autoupdate-55554944" : "org.sparkle-project.\(name)"
            return InvocationResult(
                commandLine: invocation.commandLine, status: 0, standardError: "Identifier=\(identifier)\n")
        case "sign_update" where arguments.contains("-p"):
            output = "c2lnbmF0dXJl\n"
        case "defaults":
            return InvocationResult(commandLine: invocation.commandLine, status: 1, standardError: "Domain not found")
        default:
            break
        }
        return InvocationResult(commandLine: invocation.commandLine, status: 0, standardOutput: output)
    }

    private func launch(_ executable: URL) throws {
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let caseName = app.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        guard let testCase = UpdateCase(rawValue: caseName) else { return }
        let plist = app.appending(path: "Contents/Info.plist")
        var info = try required(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
        let expected = UpdateEvents.expected(for: testCase)
        let events = overrides[testCase].map(UpdateEvents.text) ?? expected.events
        try Data(events.utf8).write(to: URL(filePath: try required(info["TestResultPath"] as? String)))
        if expected.version == "2" {
            info["CFBundleVersion"] = "2"
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
            inspector.add(202, path: executable.path, lookups: 3)
        }
        let identifier = try required(info["CFBundleIdentifier"] as? String)
        try FileManager.default.createDirectory(
            at: home.appending(path: "Library/Caches/\(identifier)"), withIntermediateDirectories: true)
    }
}

/// A missing value is a broken simulation.
private func required<T>(_ value: T?) throws -> T {
    guard let value else { throw DevFailure.checkFailed("The simulation is missing a value.") }
    return value
}
