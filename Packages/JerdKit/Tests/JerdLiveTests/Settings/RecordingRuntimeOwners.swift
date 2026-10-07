import Foundation
import JerdDatabases
import JerdMail
import JerdRuntimes
import JerdStorage

@testable import JerdLive

/// Runtime owners that return set records and record every activation.
actor RecordingRuntimeOwners: RuntimeOwning {
    enum Call: Equatable {
        case database(DatabaseRuntime)
        case mail(MailRuntime)
        case storage(StorageRuntime)
        case tunnel(URL)
        case companion(String)
        case lzma
    }

    private(set) var calls: [Call] = []
    var recordsResult: RuntimeRecords
    let lzma: SupportLibrary?

    init(records: RuntimeRecords = RuntimeRecords(), lzma: SupportLibrary? = nil) {
        recordsResult = records
        self.lzma = lzma
    }

    func records() -> RuntimeRecords { recordsResult }

    func bundledLZMA() -> SupportLibrary? {
        calls.append(.lzma)
        return lzma
    }

    func registerDatabaseRuntime(_ runtime: DatabaseRuntime) { calls.append(.database(runtime)) }
    func updateMailRuntime(_ runtime: MailRuntime) { calls.append(.mail(runtime)) }
    func updateStorageRuntime(_ runtime: StorageRuntime) { calls.append(.storage(runtime)) }
    func useTunnelRuntime(at executable: URL) { calls.append(.tunnel(executable)) }
    func activateCompanion(_ runtime: ManagedRuntime) { calls.append(.companion(runtime.id)) }
}
