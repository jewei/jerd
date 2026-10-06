import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

/// Review web-r1 L6: the old layout kept the first pool in `configuration/` and `logs/fpm.log`.
@Suite struct LegacyPoolFilesTests {
    /// The `php.ini` that the old app wrote for its first pool.
    static let oldINI = """
        [PHP]
        date.timezone = UTC
        expose_php = Off
        log_errors = On
        memory_limit = 256M
        upload_max_filesize = 32M
        post_max_size = 40M
        max_execution_time = 30
        display_errors = Off
        cgi.fix_pathinfo = 0
        [opcache]
        opcache.enable = 1
        opcache.validate_timestamps = 1
        opcache.revalidate_freq = 0

        """

    @Test func aStartRemovesTheGeneratedFilesOfTheOldFirstPool() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let environment = layout.environment
        try writeOldPool(environment, trust: true)
        _ = try await harness.start(try harness.plan(), layout: layout)
        #expect(isAbsent(environment.fpmConfigurationFile))
        #expect(isAbsent(environment.phpINIFile))
        #expect(isAbsent(environment.fpmLogFile))
        #expect(!isAbsent(environment.caddyConfigurationFile))
        await harness.engine.stop()
    }

    @Test func aLivePreviousProcessKeepsTheOldFiles() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let environment = layout.environment
        try writeOldPool(environment, trust: false)
        try OwnedDirectory.create(environment.processesDirectory)
        try writeRecord(pid: 4_242, to: environment.processRecord(UUID()).recordFile)
        _ = harness.processes.live.withLock { $0.insert(4_242) }
        await #expect(throws: JerdError.self) { try await harness.start(try harness.plan(), layout: layout) }
        #expect(!isAbsent(environment.fpmConfigurationFile))
        #expect(!isAbsent(environment.phpINIFile))
        #expect(!isAbsent(environment.fpmLogFile))
    }

    @Test func filesThatJerdDidNotWriteAreKept() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let environment = layout.environment
        try OwnedDirectory.create(environment.configurationDirectory)
        try OwnedDirectory.create(environment.logsDirectory)
        try AtomicFile.write(Data("[www]\nlisten = 9000\n".utf8), to: environment.fpmConfigurationFile)
        try AtomicFile.write(Data("[PHP]\nmemory_limit = 1G\n".utf8), to: environment.phpINIFile)
        let target = environment.root.appendingPathComponent("kept.log")
        try AtomicFile.write(Data("user notes\n".utf8), to: target)
        try FileManager.default.createSymbolicLink(at: environment.fpmLogFile, withDestinationURL: target)
        _ = try await harness.start(try harness.plan(), layout: layout)
        #expect(text(environment.fpmConfigurationFile) == "[www]\nlisten = 9000\n")
        #expect(text(environment.phpINIFile) == "[PHP]\nmemory_limit = 1G\n")
        #expect(FileProbe.presence(at: environment.fpmLogFile) == .present)
        #expect(text(target) == "user notes\n")
        await harness.engine.stop()
    }

    @Test func theRecognitionRulesMatchOnlyTheOldGeneratedText() throws {
        let pool = try FPMPoolRenderer.render(socket: URL(fileURLWithPath: "/tmp/jerd-ABC/php-0.sock"))
        #expect(LegacyPoolFiles.isGeneratedPool(pool))
        #expect(LegacyPoolFiles.isGeneratedINI(Self.oldINI))
        #expect(LegacyPoolFiles.isGeneratedINI(Self.oldINI + "\n[curl]\ncurl.cainfo = \"/x\"\n"))
        #expect(LegacyPoolFiles.isGeneratedINI(PHPIniPolicy.fpm))
        #expect(!LegacyPoolFiles.isGeneratedPool("[global]\n[www]\nlisten = 9000\n"))
        #expect(!LegacyPoolFiles.isGeneratedINI("[PHP]\nmemory_limit = 1G\n"))
        #expect(!LegacyPoolFiles.isGeneratedINI(""))
    }

    private func writeOldPool(_ environment: EnvironmentLayout, trust: Bool) throws {
        try OwnedDirectory.create(environment.root)
        try OwnedDirectory.create(environment.configurationDirectory)
        try OwnedDirectory.create(environment.logsDirectory)
        let socket = URL(fileURLWithPath: "/tmp/jerd-OLDRUN000000/php-0.sock")
        try AtomicFile.write(
            Data(try FPMPoolRenderer.render(socket: socket).utf8), to: environment.fpmConfigurationFile)
        let section =
            trust ? "\n[curl]\ncurl.cainfo = \"/x/php-ca.pem\"\n[openssl]\nopenssl.cafile = \"/x/php-ca.pem\"\n" : ""
        try AtomicFile.write(Data((Self.oldINI + section).utf8), to: environment.phpINIFile)
        try AtomicFile.write(Data("NOTICE: fpm is running\n".utf8), to: environment.fpmLogFile)
    }

    private func writeRecord(pid: pid_t, to file: URL) throws {
        let identity = ProcessIdentity(
            processID: pid, userID: geteuid(), startedSeconds: 1, startedMicroseconds: 0, bootSeconds: 0,
            executable: "/fake", auditWords: [1, 2, 3, 4, 5, 6, 7, 8], bootSessionID: "TEST")
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "PHP 8.4.0", identity: identity, controller: identity,
                gracefulSignal: SIGQUIT),
            to: file)
    }
}
