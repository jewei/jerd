import Foundation
import JerdFoundation
import Testing

@testable import JerdProcess

@Suite struct SpawnPlanTests {
    private let folder = URL(fileURLWithPath: "/tmp/work folder")

    private func request(_ environment: [String: String] = [:], arguments: [String] = ["-v"]) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: arguments, workingDirectory: folder,
            environment: environment)
    }

    @Test func theEnvironmentIsExplicitSortedAndNeverInherited() throws {
        setenv("JERD_TEST_INHERITED", "leak", 1)
        defer { unsetenv("JERD_TEST_INHERITED") }
        let plan = try SpawnPlan(request: request(["ZED": "1", "ALPHA": "2"]))
        #expect(
            plan.environment == [
                "ALPHA=2", "HOME=/tmp/work folder", "LANG=en_US.UTF-8", "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "ZED=1",
            ])
    }

    @Test func requestedVariablesReplaceTheDefaults() throws {
        let plan = try SpawnPlan(request: request(["HOME": "/custom", "PATH": "/opt/bin"]))
        #expect(plan.environment == ["HOME=/custom", "LANG=en_US.UTF-8", "PATH=/opt/bin"])
    }

    @Test func argumentsStartWithTheExecutableAndKeepTheirOrder() throws {
        let plan = try SpawnPlan(request: request(arguments: ["b", "a", ""]))
        #expect(plan.executablePath == "/usr/bin/env")
        #expect(plan.arguments == ["/usr/bin/env", "b", "a", ""])
        #expect(plan.workingDirectory == "/tmp/work folder")
    }

    @Test func descriptorsAreNullOutputOutputAndListenersOnlyWhenGiven() throws {
        let plan = try SpawnPlan(request: request())
        #expect(plan.descriptors.map(\.target) == [0, 1, 2])
        #expect(plan.descriptors.map(\.source) == [.nullDevice, .output, .output])
        let handles = InheritedListeners(http: FileHandle.nullDevice, https: FileHandle.nullDevice)
        var withListeners = request()
        withListeners.listeners = handles
        let listening = try SpawnPlan(request: withListeners)
        #expect(listening.descriptors.map(\.target) == [0, 1, 2, 3, 4])
        #expect(listening.descriptors.suffix(2).map(\.source) == [.httpListener, .httpsListener])
    }

    @Test func nulCharactersAreRefusedInArgumentsAndVariables() {
        let message = JerdError.invalid("Process arguments cannot contain NUL characters.")
        #expect(throws: message) { try SpawnPlan(request: request(arguments: ["a\0b"])) }
        #expect(throws: message) { try SpawnPlan(request: request(["KEY": "x\0y"])) }
    }

    @Test(arguments: ["", "A=B"])
    func unsafeVariableNamesAreRefused(_ name: String) {
        #expect(throws: JerdError.invalid("Process environment names cannot be empty or contain \"=\".")) {
            try SpawnPlan(request: request([name: "value"]))
        }
    }

    @Test func aNonFileExecutableURLIsRefused() {
        let remote = ProcessRequest(
            executable: URL(string: "https://example.test/tool") ?? folder, workingDirectory: folder)
        #expect(throws: JerdError.self) { try SpawnPlan(request: remote) }
    }

    @Test func spawningAsRootIsRefusedBeforeAnyFileIsCreated() throws {
        let plan = try SpawnPlan(request: request())
        #expect(throws: JerdError.processFailed("Jerd cannot run runtime processes as root.")) {
            try Spawner.requireSpawnable(plan, listeners: nil, effectiveUserID: 0)
        }
        try Spawner.requireSpawnable(plan, listeners: nil, effectiveUserID: 501)
    }

    @Test func aMissingOrNonExecutableFileIsRefused() throws {
        let missing = try SpawnPlan(
            request: ProcessRequest(executable: URL(fileURLWithPath: "/missing/jerd-binary"), workingDirectory: folder))
        #expect(throws: JerdError.processFailed("Executable is missing or is not executable: /missing/jerd-binary")) {
            try Spawner.requireSpawnable(missing, listeners: nil)
        }
        let plain = try SpawnPlan(
            request: ProcessRequest(executable: URL(fileURLWithPath: "/etc/hosts"), workingDirectory: folder))
        #expect(throws: JerdError.self) { try Spawner.requireSpawnable(plain, listeners: nil) }
    }
}
