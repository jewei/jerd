import Foundation
import JerdFoundation
import JerdRuntimes
import Testing

@Suite struct RedisClockPatchTests {
    /// The shape of `src/monotonic.c` in Redis 8.8.3: the counter functions and their selection.
    static let monotonicSource = """
        #if defined(__aarch64__)
        static void monotonicInit_aarch64(void) {}
        #endif

        const char * monotonicInit(void) {
            #if defined(__aarch64__)
            if (getMonotonicUs == NULL) monotonicInit_aarch64();
            #endif
        }

        """

    @Test func bothCounterBlocksNeedTheProcessorClockFlagThatTheBuildNeverSets() throws {
        let patched = try RedisClockPatch.apply(to: Self.monotonicSource)
        #expect(!patched.contains(RedisClockPatch.counterGuard))
        #expect(patched.components(separatedBy: RedisClockPatch.patchedGuard).count == 3)
        #expect(
            patched.contains("    #if defined(USE_PROCESSOR_CLOCK) && defined(__aarch64__)\n    if (getMonotonicUs"))
    }

    @Test(arguments: [0, 1, 3])
    func aSourceWithAnotherClockSelectionIsRefused(_ guards: Int) {
        let text = Array(repeating: "#if defined(__aarch64__)\n#endif\n", count: guards).joined()
        #expect(throws: RedisClockPatch.unexpectedSource) { try RedisClockPatch.apply(to: text) }
    }

    @Test func anAlreadyPatchedSourceIsRefused() throws {
        let patched = try RedisClockPatch.apply(to: Self.monotonicSource)
        #expect(throws: RedisClockPatch.unexpectedSource) { try RedisClockPatch.apply(to: patched) }
    }

    @Test func theFileInTheSourceIsPatchedInPlace() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let file = folder.url.appendingPathComponent(RedisClockPatch.file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.monotonicSource.utf8).write(to: file)
        try RedisClockPatch.apply(in: folder.url)
        #expect(try String(contentsOf: file, encoding: .utf8) == RedisClockPatch.apply(to: Self.monotonicSource))
    }

    @Test func aSourceWithoutTheClockFileIsRefused() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        #expect(throws: RedisClockPatch.unexpectedSource) { try RedisClockPatch.apply(in: folder.url) }
    }
}
