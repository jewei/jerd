import Darwin
import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@testable import JerdDevKit

@Suite("The minimum macOS of the embedded payloads")
struct PayloadMinimumMacOSTests {
    static let newer = "Load command 9\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform 1\n    minos 27.0\n"

    /// Replaces the executable of the `kind` payload with `data` and writes its receipt again.
    private func replaceExecutable(_ kind: RuntimeKind, with data: Data, in repository: Repository) throws {
        let folder = try PayloadFixtures.writePayload(kind, in: repository.payloads)
        let executable = folder.appending(path: "bin/\(kind.rawValue)")
        try data.write(to: executable)
        chmod(executable.path, 0o700)
        let receiptFile = folder.appending(path: PayloadReceipt.fileName)
        let old = try PayloadReceipt.decode(Data(contentsOf: receiptFile))
        var files = old.fileRecords
        files[try PayloadFixtures.relative("bin/\(kind.rawValue)")] = PayloadFileRecord(
            sha256: FileDigest.hexSHA256(of: data), executable: true)
        let receipt = PayloadReceipt(
            id: old.id, kind: old.kind, version: old.version, releaseVersion: old.releaseVersion,
            architecture: old.architecture, archiveSHA256: old.archiveSHA256, executable: old.executable,
            secondaryExecutable: old.secondaryExecutable, files: files)
        try receipt.encoded().write(to: receiptFile)
    }

    /// Compiles a tiny arm64 program with the minimum `version`.
    private func compiledProgram(minimum version: String, in folder: URL) async throws -> Data {
        let source = folder.appending(path: "main.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: source)
        let binary = folder.appending(path: "main-\(version)")
        let compile = Invocation(
            executable: URL(filePath: "/usr/bin/xcrun"),
            arguments: ["clang", "-arch", "arm64", "-mmacosx-version-min=\(version)", source.path, "-o", binary.path],
            timeout: .seconds(120))
        try await ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups()).runChecked(
            compile, output: .capture)
        return try Data(contentsOf: binary)
    }

    @Test("Verify refuses an embedded file with a newer minimum, and names the file and both versions")
    func verifyRefusesNewerEmbeddedFile() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try replaceExecutable(.redis, with: Data(PayloadFixture.machO), in: repository)
        let output = RecordingTextOutput()
        let context = TestFixtures.context(
            repository: repository,
            runner: RecordingProcessRunner {
                InvocationResult(commandLine: $0.commandLine, status: 0, standardOutput: Self.newer)
            },
            output: output)
        await #expect(throws: DevFailure.self) { try await RuntimesVerifyStep.verify(context, groups: [.database]) }
        let redis = try PayloadFixtures.pin(.redis).id
        #expect(
            output.all.contains(
                "\(redis): bin/redis: it needs macOS 27.0, above the deployment target 14.0 of the app"))
        #expect(output.all.contains("remove .build/runtimes/payloads/database/\(redis)"))
    }

    @Test("An on-demand payload may need a newer macOS: the app checks its release before it installs it")
    func onDemandPayloadIsExempt() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try replaceExecutable(.mysql, with: Data(PayloadFixture.machO), in: repository)
        let context = TestFixtures.context(
            repository: repository,
            runner: RecordingProcessRunner {
                InvocationResult(commandLine: $0.commandLine, status: 0, standardOutput: Self.newer)
            })
        let entry = try #require(
            PayloadInventory(root: repository.payloads, catalog: try PayloadFixtures.catalog())
                .entry(for: try PayloadFixtures.pin(.mysql), group: .database).payload)
        let check = PayloadDependencyCheck(context: context)
        #expect(try await check.problems(in: entry, minimumMacOS: nil).isEmpty)
        #expect(try await check.problems(in: entry, minimumMacOS: .jerdKitMinimum).count == 1)
    }

    @Test("A real binary built for macOS 27.0 fails, and the same program built for 14.0 passes")
    func realBinaryMinimumIsChecked() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let work = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let context = TestFixtures.context(
            repository: repository, runner: ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups()))
        let pin = try PayloadFixtures.pin(.redis)
        let check = PayloadDependencyCheck(context: context)
        try replaceExecutable(.redis, with: try await compiledProgram(minimum: "27.0", in: work), in: repository)
        let newer = try #require(
            PayloadInventory(root: repository.payloads, catalog: try PayloadFixtures.catalog())
                .entry(for: pin, group: .database).payload)
        #expect(
            try await check.problems(in: newer, minimumMacOS: .jerdKitMinimum) == [
                "bin/redis: it needs macOS 27.0, above the deployment target 14.0 of the app "
                    + "(MACOSX_DEPLOYMENT_TARGET in Configuration/Base.xcconfig)."
            ])
        try FileManager.default.removeItem(at: repository.payloads)
        try replaceExecutable(.redis, with: try await compiledProgram(minimum: "14.0", in: work), in: repository)
        let current = try #require(
            PayloadInventory(root: repository.payloads, catalog: try PayloadFixtures.catalog())
                .entry(for: pin, group: .database).payload)
        #expect(try await check.problems(in: current, minimumMacOS: .jerdKitMinimum).isEmpty)
    }

    @Test("The minimum comes from MACOSX_DEPLOYMENT_TARGET, and an invalid value fails")
    func minimumComesFromBaseConfiguration() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        #expect(try repository.runtimeMinimumMacOS() == MinimumMacOS(major: 14, minor: 0))
        try TestFixtures.write(
            "MACOSX_DEPLOYMENT_TARGET = 15.2\n", to: "Configuration/Base.xcconfig", in: repository.root)
        #expect(try repository.runtimeMinimumMacOS() == MinimumMacOS(major: 15, minor: 2))
        try TestFixtures.write(
            "MACOSX_DEPLOYMENT_TARGET = latest\n", to: "Configuration/Base.xcconfig", in: repository.root)
        #expect(throws: DevFailure.self) { try repository.runtimeMinimumMacOS() }
    }
}
