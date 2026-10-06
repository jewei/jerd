import Foundation
import JerdFoundation
import JerdWeb
import Testing

@testable import JerdCLICore

@Suite struct CLILauncherTests {
    private func launcher(
        _ fixture: CLIFixture, bundles: FakeCABundles = FakeCABundles(.success(nil)),
        image: RecordingProcessImage = RecordingProcessImage(),
        diagnostics: RecordingDiagnostics = RecordingDiagnostics()
    ) -> CLILauncher {
        CLILauncher(layout: fixture.layout, caBundles: bundles, processImage: image, diagnostics: diagnostics)
    }

    private func invocation(
        _ arguments: [String], environment: [String: String] = ["PATH": "/usr/bin:/bin"], directory: String? = "/"
    ) -> CLIInvocation {
        CLIInvocation(arguments: arguments, environment: environment, workingDirectory: directory)
    }

    @Test func phpOutsideProjectsUsesTheDefaultWithJerdINI() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let php = try fixture.installPHP("8.5")
        try fixture.saveDefault(php)
        let plan = try launcher(fixture).prepare(invocation(["php", "-v"]))
        let runtimes = fixture.layout.runtimes
        #expect(plan.argumentText == [php.cliPath, "-c", runtimes.cliINIFile.path, "-v"])
        #expect(plan.environment.text("PHP_INI_SCAN_DIR") == runtimes.cliEmptyINIDirectory.path)
        #expect(plan.environment.text("PATH") == fixture.layout.binDirectory.path + ":/usr/bin:/bin")
        #expect(text(runtimes.cliINIFile).hasPrefix(PHPIniPolicy.cli))
    }

    @Test func siteDirectoryUsesTheSitePin() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let normal = try fixture.installPHP("8.5")
        let pinned = try fixture.installPHP("8.4")
        let site = try fixture.site("app", project: "code/app", selection: .pinned(pinned.id), enabled: false)
        try fixture.saveDefault(normal, sites: [site], others: [pinned])
        let nested = try fixture.directory.folder("code/app/src")
        let plan = try launcher(fixture).prepare(invocation(["php"], directory: nested.path))
        #expect(plan.executable == pinned.cliPath)
    }

    @Test func composerAndLaravelRunTheirRecordedScripts() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let php = try fixture.installPHP("8.5")
        try fixture.saveDefault(php)
        let companions = try fixture.installCompanions()
        let composer = try launcher(fixture).prepare(invocation(["composer", "-n", "install"]))
        #expect(
            composer.argumentText == [
                php.cliPath, "-c", fixture.layout.runtimes.cliINIFile.path, companions.composerPath, "-n", "install",
            ])
        let laravel = try launcher(fixture).prepare(invocation(["/x/laravel", "new", "blog"]))
        #expect(Array(laravel.argumentText.suffix(3)) == [companions.laravelPath, "new", "blog"])
    }

    @Test(arguments: [CLICommand.composer, .laravel])
    func missingToolRecordGivesTheFriendlyMessage(command: CLICommand) throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        let expected = "The Jerd \(command.rawValue) tool is unavailable. Open Jerd to install its bundled tools."
        #expect(throws: JerdError.unavailable(expected)) {
            try launcher(fixture).prepare(invocation([command.rawValue]))
        }
        let companions = try fixture.installCompanions()
        try FileManager.default.removeItem(
            atPath: command == .composer ? companions.composerPath : companions.laravelPath)
        #expect(throws: JerdError.unavailable(expected)) {
            try launcher(fixture).prepare(invocation([command.rawValue]))
        }
    }

    @Test func corruptToolRecordIsPreservedAndReported() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        try AtomicFile.write(Data("{".utf8), to: fixture.layout.runtimes.cliToolsFile)
        #expect(throws: JerdError.self) { try launcher(fixture).prepare(invocation(["composer"])) }
        #expect(text(fixture.layout.runtimes.cliToolsFile) == "{")
    }

    @Test func missingConfigurationAsksForADefault() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        #expect(throws: JerdError.unavailable("Select a default PHP runtime in Jerd.")) {
            try launcher(fixture).prepare(invocation(["php"]))
        }
    }

    @Test func corruptConfigurationIsPreservedAndReported() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try AtomicFile.write(Data("not json".utf8), to: fixture.layout.configurationFile)
        #expect {
            try launcher(fixture).prepare(invocation(["php"]))
        } throws: { error in
            (error as? JerdError)?.kind == .corrupt
        }
        #expect(text(fixture.layout.configurationFile) == "not json")
    }

    @Test func unsupportedConfigurationVersionIsRejectedByTheStore() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try AtomicFile.write(Data(#"{"schemaVersion":2,"sites":[]}"#.utf8), to: fixture.layout.configurationFile)
        #expect {
            try launcher(fixture).prepare(invocation(["php"]))
        } throws: { error in
            FailureDetail.describe(error).contains("Unsupported configuration version: 2.")
        }
    }

    @Test func versionZeroConfigurationIsMigratedInMemory() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let bytes = Data(#"{"schemaVersion":0,"sites":[]}"#.utf8)
        try AtomicFile.write(bytes, to: fixture.layout.configurationFile)
        #expect(throws: JerdError.unavailable("Select a default PHP runtime in Jerd.")) {
            try launcher(fixture).prepare(invocation(["php"]))
        }
        #expect(contents(fixture.layout.configurationFile) == bytes)
    }

    @Test func missingPHPNamesTheSelectorAndPath() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let missing = fixture.runtime("8.3", cliPath: "/nowhere/php")
        let site = try fixture.site("app", project: "code/app", selection: .pinned(missing.id))
        try fixture.saveDefault(missing, sites: [site])
        #expect(throws: JerdError.unavailable("PHP 8.3 selected for the default is unavailable: /nowhere/php")) {
            try launcher(fixture).prepare(invocation(["php"]))
        }
        let project = fixture.directory.path("code/app").path
        #expect(throws: JerdError.unavailable("PHP 8.3 selected for app.test is unavailable: /nowhere/php")) {
            try launcher(fixture).prepare(invocation(["php"], directory: project))
        }
    }

    @Test func nonExecutablePHPIsUnavailable() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let php = try fixture.installPHP("8.5")
        chmod(php.cliPath, 0o600)
        try fixture.saveDefault(php)
        #expect(throws: JerdError.self) { try launcher(fixture).prepare(invocation(["php"])) }
    }

    @Test func unreadableWorkingDirectoryIsReported() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        #expect(
            throws: JerdError.unavailable(
                "Cannot read the current folder. Change to an existing folder and try again.")
        ) { try launcher(fixture).prepare(invocation(["php"], directory: nil)) }
    }

    @Test func trustedLocalCAUsesTheLocalTLSINI() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        let bundle = fixture.layout.runtimes.cliCABundleFile
        let bundles = FakeCABundles(.success(bundle))
        let plan = try launcher(fixture, bundles: bundles).prepare(invocation(["php"]))
        #expect(plan.argumentText[2] == fixture.layout.runtimes.cliLocalTLSINIFile.path)
        #expect(text(fixture.layout.runtimes.cliLocalTLSINIFile).contains("openssl.cafile = \"\(bundle.path)\""))
        #expect(bundles.callCount == 1)
    }

    @Test(arguments: [
        (["php", "-n"], [String: String]()),
        (["php"], ["PHPRC": "/etc"]),
        (["php"], ["SSL_CERT_FILE": "/ca.pem"]),
        (["composer"], ["CURL_CA_BUNDLE": "/ca.pem"]),
    ])
    func explicitUserChoicesSkipTheLocalCA(arguments: [String], environment: [String: String]) throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        try fixture.installCompanions()
        let bundles = FakeCABundles(.success(fixture.layout.runtimes.cliCABundleFile))
        let plan = try launcher(fixture, bundles: bundles).prepare(invocation(arguments, environment: environment))
        #expect(bundles.callCount == 0)
        #expect(!plan.argumentText.contains(fixture.layout.runtimes.cliLocalTLSINIFile.path))
    }

    @Test func userScanFolderStaysUnchanged() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        let plan = try launcher(fixture).prepare(invocation(["php"], environment: ["PHP_INI_SCAN_DIR": "/fragments"]))
        #expect(plan.environment.text("PHP_INI_SCAN_DIR") == "/fragments")
        #expect(isAbsent(fixture.layout.runtimes.cliEmptyINIDirectory))
    }

    @Test func caFailureDegradesToNoLocalCAWithOneWarning() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        let diagnostics = RecordingDiagnostics()
        let bundles = FakeCABundles(.failure(.corrupt("The installation identity is invalid. It was preserved.")))
        let plan = try launcher(fixture, bundles: bundles, diagnostics: diagnostics).prepare(invocation(["php", "-v"]))
        #expect(plan.argumentText[2] == fixture.layout.runtimes.cliINIFile.path)
        #expect(
            diagnostics.recorded == [
                "Jerd: warning: PHP runs without the local HTTPS CA. The installation identity is invalid. It was preserved."
            ])
    }

    @Test func bundlePathThatINICannotHoldDegradesToo() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        let diagnostics = RecordingDiagnostics()
        let bundles = FakeCABundles(.success(URL(fileURLWithPath: "/x/${HOME}/ca.pem")))
        let plan = try launcher(fixture, bundles: bundles, diagnostics: diagnostics).prepare(invocation(["php"]))
        #expect(plan.argumentText[2] == fixture.layout.runtimes.cliINIFile.path)
        #expect(diagnostics.recorded.count == 1)
    }

    @Test func runPrintsOneErrorLineAndExitsWithOne() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let diagnostics = RecordingDiagnostics()
        let image = RecordingProcessImage()
        let status = launcher(fixture, image: image, diagnostics: diagnostics).run(invocation(["JerdCLI"]))
        #expect(status == 1)
        #expect(image.recorded.isEmpty)
        #expect(
            diagnostics.recorded == [
                "Jerd: Run Jerd's launcher as php, composer, or laravel. To install these commands, open Jerd, go to Advanced, and choose Install Command-Line Tools."
            ])
    }

    @Test func failedExecIsReportedWithTheSystemReason() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        try fixture.saveDefault(try fixture.installPHP("8.5"))
        let diagnostics = RecordingDiagnostics()
        let image = RecordingProcessImage(failure: EACCES)
        let status = launcher(fixture, image: image, diagnostics: diagnostics).run(invocation(["php", "-v"]))
        #expect(status == CLILauncher.failureStatus)
        #expect(image.recorded.count == 1)
        #expect(diagnostics.recorded == ["Jerd: Cannot run PHP: Permission denied"])
    }

    @Test func eachInvocationReadsTheCurrentConfiguration() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let first = try fixture.installPHP("8.5")
        let second = try fixture.installPHP("8.4")
        try fixture.saveDefault(first, others: [second])
        let subject = launcher(fixture)
        #expect(try subject.prepare(invocation(["php"])).executable == first.cliPath)
        try fixture.saveDefault(second, others: [first])
        #expect(try subject.prepare(invocation(["php"])).executable == second.cliPath)
    }
}
