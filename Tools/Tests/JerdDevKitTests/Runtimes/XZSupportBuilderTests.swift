import Foundation
import JerdFoundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("XZ support library")
struct XZSupportBuilderTests {
    static let url = URL(string: "https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz")!

    /// A source archive with the files that the build reads, made with the system tar.
    private func makeArchive(in folder: URL) async throws -> Data {
        try TestFixtures.write("#!/bin/sh\n", to: "src/xz-5.8.4/configure", in: folder)
        try TestFixtures.write("0BSD", to: "src/xz-5.8.4/COPYING.0BSD", in: folder)
        let archive = folder.appending(path: "xz.tar.gz")
        let tar = Invocation(
            executable: URL(filePath: "/usr/bin/tar"),
            arguments: ["-czf", archive.path, "-C", folder.appending(path: "src").path, "xz-5.8.4"],
            timeout: .seconds(30))
        try await ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups()).runChecked(
            tar, output: .capture)
        return try Data(contentsOf: archive)
    }

    /// `make install` writes the library; every other command succeeds without output.
    private func runner() -> RecordingProcessRunner {
        RecordingProcessRunner { invocation in
            if invocation.arguments == ["install"], let source = invocation.workingDirectory {
                let library = source.deletingLastPathComponent().appending(path: "install/lib/liblzma.5.dylib")
                try FileManager.default.createDirectory(
                    at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("dylib".utf8).write(to: library)
            }
            return InvocationResult(commandLine: invocation.commandLine, status: 0)
        }
    }

    private func builder(
        _ folder: URL, archive: Data, runner: RecordingProcessRunner, fetcher: FakeFetcher
    )
        -> XZSupportBuilder
    {
        let source = PinnedSupportSource(
            version: "5.8.4",
            archive: PinnedArchive(url: Self.url, size: Int64(archive.count), sha256: FileDigest.hexSHA256(of: archive))
        )
        return XZSupportBuilder(
            folder: folder.appending(path: "support/xz"), source: source, deploymentTarget: "14.0",
            fetcher: fetcher, context: TestFixtures.context(runner: runner, environment: ["HOME": "/Users/me"]))
    }

    @Test("Builds, renames the install ID, signs ad hoc, records digests, and then reuses the build")
    func buildsAndReuses() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = try await makeArchive(in: folder)
        let runner = runner()
        let fetcher = FakeFetcher(files: [Self.url: archive])
        let library = try await builder(folder, archive: archive, runner: runner, fetcher: fetcher).build()
        #expect(try Data(contentsOf: library.library) == Data("dylib".utf8))
        #expect(try Data(contentsOf: library.license) == Data("0BSD".utf8))
        let programs = runner.recorded.map(\.executable.lastPathComponent)
        #expect(programs == ["configure", "make", "make", "install_name_tool", "codesign"])
        #expect(Array(runner.recorded[3].arguments.dropLast()) == ["-id", "@rpath/liblzma.5.dylib"])
        #expect(Array(runner.recorded[4].arguments.dropLast()) == ["--force", "--sign", "-"])
        #expect(runner.recorded[4].arguments.last?.hasSuffix("/xz/liblzma.5.dylib") == true)
        let receipt = try #require(try SupportReceipt.read(from: folder.appending(path: "support/xz")))
        #expect(receipt.files["liblzma.5.dylib"] == FileDigest.hexSHA256(of: Data("dylib".utf8)))
        _ = try await builder(folder, archive: archive, runner: runner, fetcher: fetcher).build()
        #expect(fetcher.requested.count == 1)
        #expect(runner.recorded.count == 5)
    }

    @Test("A download that does not match the pin stops the build")
    func refusesWrongArchive() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = try await makeArchive(in: folder)
        let fetcher = FakeFetcher(files: [Self.url: Data("other".utf8) + archive.dropFirst(5)])
        await #expect(throws: DevFailure.self) {
            _ = try await builder(folder, archive: archive, runner: runner(), fetcher: fetcher).build()
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "support/xz").path))
    }

    @Test("A failed compiler step stops the build and leaves no library")
    func failedStepLeavesNothing() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = try await makeArchive(in: folder)
        let failing = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 2) }
        await #expect(throws: DevFailure.self) {
            _ = try await builder(
                folder, archive: archive, runner: failing, fetcher: FakeFetcher(files: [Self.url: archive])
            ).build()
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "support/xz").path))
    }

    @Test("The build uses a fixed environment and the deployment target of the app")
    func planUsesFixedEnvironment() {
        let plan = XZBuildPlan(
            source: URL(filePath: "/s"), install: URL(filePath: "/i"), deploymentTarget: "14.0", processors: 8,
            inherited: ["HOME": "/Users/me", "PATH": "/opt/homebrew/bin", "CFLAGS": "-O0"])
        #expect(plan.environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(plan.environment["MACOSX_DEPLOYMENT_TARGET"] == "14.0")
        #expect(plan.environment["CFLAGS"] == "-O2 -arch arm64 -mmacosx-version-min=14.0")
        #expect(plan.environment["LDFLAGS"] == "-arch arm64 -mmacosx-version-min=14.0")
        #expect(plan.environment["HOME"] == "/Users/me")
        #expect(plan.buildSteps.map(\.arguments.first) == ["--prefix=/i", "-j8", "install"])
        #expect(plan.buildSteps[0].arguments.contains("--disable-xz"))
    }

    @Test("A receipt matches only the same pin and deployment target, and detects changed files")
    func receiptRules() throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestFixtures.write("a", to: "a", in: folder)
        let receipt = SupportReceipt(
            name: "xz", version: "5.8.4", archiveSHA256: String(repeating: "a", count: 64),
            deploymentTarget: "14.0", files: ["a": FileDigest.hexSHA256(of: Data("a".utf8))])
        let source = PinnedSupportSource(
            version: "5.8.4", archive: PinnedArchive(url: Self.url, size: 1, sha256: String(repeating: "a", count: 64)))
        #expect(receipt.matches(source, deploymentTarget: "14.0"))
        #expect(!receipt.matches(source, deploymentTarget: "15.0"))
        try receipt.verify(in: folder)
        try TestFixtures.write("b", to: "b", in: folder)
        #expect(throws: JerdError.self) { try receipt.verify(in: folder) }
    }
}
