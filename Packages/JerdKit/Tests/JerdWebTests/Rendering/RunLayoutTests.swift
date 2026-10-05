import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct RunLayoutTests {
    let data = DataLayout(root: URL(fileURLWithPath: "/Users/u/Library/Application Support/Jerd"))

    @Test func theProductRunUsesTheEnvironmentFolderAndTheInstallationCA() {
        let id = UUID()
        let layout = RunLayout.product(environment: data.environment, installationID: id)
        #expect(layout.authority == .installation(id))
        #expect(layout.rootCertificateFile == data.environment.rootCertificateFile)
        #expect(layout.socketDirectory.lastPathComponent.hasPrefix("jerd-"))
        #expect(layout.socketDirectory.lastPathComponent.count == 17)
        #expect(
            layout.socketDirectory.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL)
        #expect(
            RunLayout.product(environment: data.environment, installationID: id).socketDirectory
                != layout.socketDirectory)
    }

    @Test func poolsAreKeyedByRuntimeID() {
        let layout = RunLayout.product(environment: data.environment, installationID: UUID())
        let runtime = UUID()
        let pool = layout.pool(runtimeID: runtime, index: 2)
        #expect(pool.directory == data.environment.phpRuntimeDirectory(runtime))
        #expect(pool.fpmConfigurationFile.path.hasSuffix("php/\(runtime.uuidString)/configuration/php-fpm.conf"))
        #expect(pool.phpINIFile.path.hasSuffix("php/\(runtime.uuidString)/configuration/php.ini"))
        #expect(pool.logFile.path.hasSuffix("php/\(runtime.uuidString)/logs/fpm.log"))
        #expect(pool.socket == layout.socketDirectory.appendingPathComponent("php-2.sock"))
    }

    @Test func theProductSocketPathFitsTheUnixLimit() {
        let layout = RunLayout.product(environment: data.environment, installationID: UUID())
        #expect(layout.pool(runtimeID: UUID(), index: 99).socket.path.utf8.count < RunLayout.socketPathLimit)
    }

    @Test func aPreflightRunUsesAThrowawayTreeAndTheIsolatedCA() {
        let layout = RunLayout.preflight(within: data.environment)
        #expect(layout.authority == .isolatedTest)
        #expect(layout.preflightTree.lastPathComponent.hasPrefix("preflight-"))
        #expect(layout.preflightTree.deletingLastPathComponent() == data.environment.root)
        #expect(layout.rootCertificateFile.path.hasSuffix("certificates/pki/authorities/jerd-test/root.crt"))
        #expect(layout.socketDirectory.lastPathComponent.hasPrefix("jerd-pf-"))
    }

    @Test func childProcessesGetExactlyTheThreeRunVariables() {
        let layout = RunLayout.product(environment: data.environment, installationID: UUID())
        #expect(
            layout.processEnvironment == [
                "PHP_INI_SCAN_DIR": data.environment.emptyINIDirectory.path,
                "XDG_DATA_HOME": data.environment.certificatesDirectory.path,
                "XDG_CONFIG_HOME": data.environment.configurationDirectory.path,
            ])
    }
}
