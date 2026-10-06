import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing

@testable import JerdDevKit

@Suite("Runtime prepare gives each pin the tools of the pins before it")
struct RuntimesPrepareToolsTests {
    private func preparer(_ repository: Repository) -> PinnedPayloadPreparer {
        PinnedPayloadPreparer(
            catalogDirectory: repository.runtimeSources, output: repository.payloads, fetcher: FakeFetcher(files: [:]),
            commands: CommandRunner())
    }

    @Test("Composer gets the PHP CLI that the same run prepared")
    func composerGetsPreparedPHP() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let php = try PayloadFixtures.writePayload(.php, in: repository.payloads)
        let tools = try RuntimesPrepareStep.tools(
            for: try PayloadFixtures.pin(.composer), preparer: preparer(repository),
            catalog: try PayloadFixtures.catalog(), lzma: nil)
        #expect(tools.phpCLI?.path == php.appending(path: "bin/php").path)
        #expect(tools.composer == nil)
    }

    @Test("The Laravel installer gets the prepared PHP CLI and composer.phar")
    func laravelGetsPHPAndComposer() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let php = try PayloadFixtures.writePayload(.php, in: repository.payloads)
        let composer = try PayloadFixtures.writePayload(.composer, in: repository.payloads)
        let tools = try RuntimesPrepareStep.tools(
            for: try PayloadFixtures.pin(.laravel), preparer: preparer(repository),
            catalog: try PayloadFixtures.catalog(), lzma: nil)
        #expect(tools.phpCLI?.path == php.appending(path: "bin/php").path)
        #expect(tools.composer?.path == composer.appending(path: "bin/composer").path)
    }

    @Test("Composer without a prepared PHP fails with the pin to prepare first")
    func composerWithoutPHPNamesThePHPPin() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let phpPin = try PayloadFixtures.pin(.php)
        do {
            _ = try RuntimesPrepareStep.tools(
                for: try PayloadFixtures.pin(.composer), preparer: preparer(repository),
                catalog: try PayloadFixtures.catalog(), lzma: nil)
            Issue.record("Expected a failure.")
        } catch let failure as DevFailure {
            #expect(failure.message.contains("Prepare \(phpPin.id) first"))
        }
    }

    @Test("PHP comes first and Composer second, whatever the catalog order")
    func preparationOrderPutsToolsFirst() throws {
        let catalog = try PayloadFixtures.catalog()
        let reversed = Array(catalog.pins(in: .development).reversed())
        #expect(RuntimesPrepareStep.preparationOrder(reversed).map(\.kind) == [.php, .composer, .laravel, .caddy])
        let database = catalog.pins(in: .database)
        #expect(RuntimesPrepareStep.preparationOrder(database).map(\.id) == database.map(\.id))
    }
}
