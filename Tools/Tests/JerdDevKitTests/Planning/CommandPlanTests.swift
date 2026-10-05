import Foundation
import Testing

@testable import JerdDevKit

@Suite("Format, generate, snapshot, and clean plans")
struct CommandPlanTests {
    private let repository = TestFixtures.repository
    private let toolchain = TestFixtures.toolchain

    @Test("formats the five Swift folders in place with the root configuration")
    func plansFormat() {
        let invocation = FormatPlan.format(repository: repository, toolchain: toolchain)
        #expect(
            invocation.arguments == [
                "swift-format", "format", "--configuration", "/work/jerd/.swift-format", "--in-place",
                "--recursive", "--parallel", "/work/jerd/Packages/JerdKit/Sources", "/work/jerd/Packages/JerdKit/Tests",
                "/work/jerd/Apps", "/work/jerd/Tools/Sources", "/work/jerd/Tools/Tests",
            ])
    }

    @Test("checks the format strictly without changes")
    func plansFormatCheck() {
        let arguments = FormatPlan.check(repository: repository, toolchain: toolchain).arguments
        #expect(
            arguments.starts(with: ["swift-format", "lint", "--configuration", "/work/jerd/.swift-format", "--strict"]))
        #expect(!arguments.contains("--in-place"))
    }

    @Test("generates from the spec in the given root")
    func plansGenerate() {
        let root = URL(filePath: "/tmp/copy")
        let invocation = GeneratePlan.generate(root: root, xcodegen: URL(filePath: "/opt/tools/xcodegen"))
        #expect(invocation.arguments == ["generate", "--quiet", "--spec", "/tmp/copy/project.yml"])
        #expect(invocation.workingDirectory == root)
    }

    @Test("lists tracked and new files without ignored files")
    func plansFileListing() {
        let invocation = GeneratePlan.listSourceFiles(repository: repository, toolchain: toolchain)
        #expect(
            invocation.arguments == [
                "-C", "/work/jerd", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
            ])
    }

    @Test("copies every listed file except the committed project")
    func filtersCommittedProject() {
        let output = "project.yml\0Jerd.xcodeproj/project.pbxproj\0Apps/Jerd/JerdApp.swift\0Jerd.xcodeproj.md\0"
        #expect(
            GeneratePlan.filesToCopy(fromGitOutput: output) == [
                "project.yml", "Apps/Jerd/JerdApp.swift", "Jerd.xcodeproj.md",
            ])
    }

    @Test("renders snapshots into .build/snapshots with the given pages")
    func plansSnapshots() {
        let invocation = SnapshotPlan.invocation(repository: repository, toolchain: toolchain, pages: ["Sites"])
        #expect(
            invocation.arguments == [
                "swift", "run", "--package-path", "/work/jerd/Packages/JerdKit", "-c", "debug", "jerd-snapshots",
                "--output", "/work/jerd/.build/snapshots", "Sites",
            ])
    }

    @Test("cleans build folders, and with --all also packages and runtimes")
    func plansClean() {
        let paths = CleanPlan.targets(repository: repository, all: false).map(repository.relativePath(of:))
        #expect(
            paths == [".build/xcode", ".build/snapshots", ".build/logs", "Packages/JerdKit/.build", "Tools/.build"])
        let all = CleanPlan.targets(repository: repository, all: true).map(repository.relativePath(of:))
        #expect(all == paths + [".build/SourcePackages", ".build/runtimes"])
    }

    @Test("removes only .build folders inside the repository")
    func guardsRemoval() {
        #expect(CleanPlan.isSafeToRemove(repository.path(".build/xcode"), repository: repository))
        #expect(CleanPlan.isSafeToRemove(repository.path("Tools/.build"), repository: repository))
        #expect(!CleanPlan.isSafeToRemove(repository.path("Packages/JerdKit"), repository: repository))
        #expect(!CleanPlan.isSafeToRemove(URL(filePath: "/tmp/.build"), repository: repository))
        #expect(!CleanPlan.isSafeToRemove(repository.root, repository: repository))
        #expect(
            CleanPlan.targets(repository: repository, all: true).allSatisfy {
                CleanPlan.isSafeToRemove($0, repository: repository)
            })
    }
}
