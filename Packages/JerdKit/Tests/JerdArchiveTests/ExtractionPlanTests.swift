import Foundation
import JerdArchive
import JerdFoundation
import Testing

@Suite struct ExtractionPlanTests {
    private func file(_ path: String, size: Int64? = 4, permissions: UInt32 = 0o644) -> ArchiveEntryHeader {
        ArchiveEntryHeader(path: path, type: .regular, size: size, permissions: permissions)
    }

    private func symlink(_ path: String, _ target: String?) -> ArchiveEntryHeader {
        ArchiveEntryHeader(path: path, type: .symbolicLink, size: 0, symlinkTarget: target)
    }

    private func hardlink(_ path: String, _ target: String) -> ArchiveEntryHeader {
        ArchiveEntryHeader(path: path, type: .regular, size: 0, hardlinkTarget: target)
    }

    private func path(_ text: String) throws -> RelativePath { try #require(RelativePath(text)) }

    private func write(_ action: EntryAction) throws -> FileWrite {
        guard case .writeFile(let write) = action else { throw JerdError.invalid("Expected a file write.") }
        return write
    }

    @Test func executableEntriesGetOwnerOnlyExecuteModeAndOthersPrivateMode() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy())
        #expect(try write(plan.admit(file("bin/tool", permissions: 0o755))).mode == 0o700)
        #expect(try write(plan.admit(file("bin/tool2", permissions: 0o010))).mode == 0o700)
        #expect(try write(plan.admit(file("notes.txt", permissions: 0o644))).mode == 0o600)
    }

    @Test func strippedRootIsSkippedAndRemovedFromEveryPath() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(stripsRoot: true))
        #expect(try plan.admit(ArchiveEntryHeader(path: "./root/", type: .directory, size: 0)) == .skip)
        #expect(try write(plan.admit(file("root/bin/tool"))).path == path("bin/tool"))
        #expect(throws: ArchiveFailure.moreThanOneRoot) { try plan.admit(file("other/x")) }
    }

    @Test func rootEntryThatIsNotAFolderIsRefused() {
        var plan = ExtractionPlan(policy: ExtractionPolicy(stripsRoot: true))
        #expect(throws: ArchiveFailure.rootNotDirectory) { try plan.admit(file("root")) }
    }

    @Test(arguments: ["../escape", "/absolute", "a/../b", "a\\b", "a/\u{1}", "", "."])
    func unsafeEntryNamesAreRefused(_ name: String) {
        var plan = ExtractionPlan(policy: ExtractionPolicy())
        #expect(throws: ArchiveFailure.unsafePath) { try plan.admit(file(name)) }
    }

    @Test func namesThatCollideByCaseOrUnicodeFormAreRefused() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy())
        _ = try plan.admit(file("Caf\u{E9}"))
        #expect(throws: ArchiveFailure.duplicatePath) { try plan.admit(file("CAFE\u{301}")) }
    }

    @Test func entryCountIncludesUnselectedEntriesAndFolders() throws {
        var policy = ExtractionPolicy(selects: { $0.string == "wanted" })
        policy.entryLimit = 2
        var plan = ExtractionPlan(policy: policy)
        #expect(try plan.admit(ArchiveEntryHeader(path: "dir", type: .directory, size: 0)) == .skip)
        #expect(try plan.admit(file("other")) == .skip)
        #expect(throws: ArchiveFailure.tooManyEntries) { try plan.admit(file("wanted")) }
    }

    @Test func everyEntryHasThePerFileSizeCapEvenWhenUnselected() {
        var policy = ExtractionPolicy(selects: { _ in false })
        policy.fileSizeLimit = 10
        var plan = ExtractionPlan(policy: policy)
        #expect(throws: ArchiveFailure.fileTooLarge) { try plan.admit(file("big", size: 11)) }
    }

    @Test func outputBudgetCountsOnlySelectedFiles() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(outputLimit: 10, selects: { $0.string != "skipped" }))
        #expect(try plan.admit(file("skipped", size: 100)) == .skip)
        _ = try plan.admit(file("kept", size: 10))
        #expect(plan.outputBytes == 10)
        #expect(throws: ArchiveFailure.outputTooLarge) { try plan.admit(file("more", size: 1)) }
    }

    @Test func entryWithoutRecordedSizeStreamsUpToTheSmallerLimit() throws {
        var policy = ExtractionPolicy(outputLimit: 100)
        policy.fileSizeLimit = 40
        var plan = ExtractionPlan(policy: policy)
        let first = try write(plan.admit(file("a", size: nil)))
        #expect(first.declaredSize == nil && first.byteLimit == 40 && first.limitFailure == ArchiveFailure.fileTooLarge)
        try plan.recordWritten(first, bytes: 40)
        _ = try plan.admit(file("b", size: 40))
        let last = try write(plan.admit(file("c", size: nil)))
        #expect(last.byteLimit == 20 && last.limitFailure == ArchiveFailure.outputTooLarge)
    }

    @Test func declaredSizeIsTheExactWriteLimit() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy())
        let write = try write(plan.admit(file("a", size: 12)))
        #expect(write.declaredSize == 12 && write.byteLimit == 12)
        #expect(write.limitFailure == ArchiveFailure.exceedsDeclaredSize)
    }

    @Test(arguments: [UInt32(0o010_000), 0o020_000, 0o060_000, 0o140_000])
    func specialFileTypesAreRefused(_ bits: UInt32) {
        var plan = ExtractionPlan(policy: ExtractionPolicy())
        let header = ArchiveEntryHeader(path: "special", type: .init(modeBits: bits), size: 0)
        #expect(throws: ArchiveFailure.unsupportedType) { try plan.admit(header) }
    }

    @Test func symbolicLinksResolveFromTheirFolderAndHardLinksFromTheTop() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(stripsRoot: true))
        _ = try plan.admit(ArchiveEntryHeader(path: "root", type: .directory, size: 0))
        #expect(
            try plan.admit(symlink("root/bin/alias", "../lib/tool"))
                == .recordLink(path: path("bin/alias"), target: path("lib/tool")))
        #expect(
            try plan.admit(hardlink("root/bin/hard", "root/lib/tool"))
                == .recordLink(path: path("bin/hard"), target: path("lib/tool")))
    }

    @Test(arguments: [
        ("root/a", "../../escape", ArchiveFailure.linkLeavesRoot), ("root/a", "/tmp/x", ArchiveFailure.unsafeLink),
        ("root/a", "x\\y", ArchiveFailure.unsafeLink), ("root/a", "..", ArchiveFailure.emptyLink),
        ("root/a", "../other/x", ArchiveFailure.linkLeavesRoot), ("root/a", "", ArchiveFailure.emptyLink),
    ])
    func unsafeSymbolicLinksAreRefused(_ name: String, _ target: String, _ failure: JerdError) throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(stripsRoot: true))
        _ = try plan.admit(ArchiveEntryHeader(path: "root", type: .directory, size: 0))
        #expect(throws: failure) { try plan.admit(symlink(name, target)) }
    }

    @Test func symbolicLinkWithoutTargetReportsAnEmptyLink() {
        var plan = ExtractionPlan(policy: ExtractionPolicy())
        #expect(throws: ArchiveFailure.emptyLink) { try plan.admit(symlink("a", nil)) }
    }

    @Test func selectedLinkToTheStrippedRootFolderIsNotAnIncludedFile() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(stripsRoot: true))
        _ = try plan.admit(ArchiveEntryHeader(path: "root", type: .directory, size: 0))
        #expect(throws: ArchiveFailure.linkTargetMissing) { try plan.admit(symlink("root/a", ".")) }
    }

    @Test func linkChainsResolveToTheFinalFileWithinTheBudget() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(outputLimit: 30))
        try plan.recordWritten(write(plan.admit(file("file", size: 10))), bytes: 10)
        _ = try plan.admit(symlink("alias", "file"))
        _ = try plan.admit(symlink("chain", "alias"))
        let copies = try plan.linkCopies()
        #expect(copies.map { "\($0.path) <- \($0.source)" } == ["alias <- file", "chain <- file"])
        #expect(plan.outputBytes == 30)
    }

    @Test func linkCopiesBeyondTheBudgetAreRefused() throws {
        var plan = ExtractionPlan(policy: ExtractionPolicy(outputLimit: 19))
        try plan.recordWritten(write(plan.admit(file("file", size: 10))), bytes: 10)
        _ = try plan.admit(symlink("alias", "file"))
        #expect(throws: ArchiveFailure.outputTooLargeAfterLinks) { try plan.linkCopies() }
    }

    @Test func linkCyclesAndLinksToMissingFilesAreRefused() throws {
        var cycle = ExtractionPlan(policy: ExtractionPolicy())
        _ = try cycle.admit(symlink("a", "b"))
        _ = try cycle.admit(symlink("b", "a"))
        #expect(throws: ArchiveFailure.linkCycle) { try cycle.linkCopies() }
        var missing = ExtractionPlan(policy: ExtractionPolicy(selects: { $0.string != "file" }))
        #expect(try missing.admit(file("file")) == .skip)
        _ = try missing.admit(symlink("alias", "file"))
        #expect(throws: ArchiveFailure.linkTargetMissing) { try missing.linkCopies() }
    }

    @Test func libraryOlderThanVersionThreeIsRefused() throws {
        #expect(throws: ArchiveFailure.libraryUnsupported) {
            try ArchiveReader.requireSupportedLibrary(version: 2_999_999)
        }
        try ArchiveReader.requireSupportedLibrary(version: 3_007_002)
    }
}
