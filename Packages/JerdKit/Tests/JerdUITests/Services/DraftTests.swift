import JerdDatabases
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Database, restore, and bucket drafts")
struct DraftTests {
    let configuration = SampleServices.databases(.populated)

    @Test("Add picks the first runtime and a free default name")
    func addDefaults() {
        var configuration = configuration
        configuration.services.append(DatabaseService(name: "MySQL", runtimeID: SampleServices.mysql.id, port: 3310))
        let draft = DatabaseDraft.add(.mysql, in: configuration)
        #expect(draft.runtimeID == SampleServices.mysql.id)
        #expect(draft.name == "MySQL 2")
        #expect(draft.portText.isEmpty)
    }

    @Test("An engine change keeps a typed name (spec F 7.2.7) and replaces a default one")
    func engineChangeKeepsTypedName() {
        var draft = DatabaseDraft.add(.mysql, in: configuration)
        draft.changeEngine(.redis, in: configuration)
        #expect(draft.name == "Redis")
        #expect(draft.runtimeID == SampleServices.redis.id)
        draft.setName("Queue")
        draft.changeEngine(.postgresql, in: configuration)
        #expect(draft.name == "Queue")
    }

    @Test("A late port suggestion never replaces a typed port or fills another engine")
    func lateSuggestion() {
        var draft = DatabaseDraft.add(.mysql, in: configuration)
        draft.applySuggestedPort(5433, for: .postgresql)
        #expect(draft.portText.isEmpty)
        draft.applySuggestedPort(3307, for: .mysql)
        #expect(draft.portText == "3307")
        draft.setPort("3399")
        draft.applySuggestedPort(3308, for: .mysql)
        #expect(draft.portText == "3399")
    }

    @Test("Each editor rule has its own inline message")
    func editorRules() {
        var draft = DatabaseDraft.add(.mysql, in: configuration)
        draft.setPort("3307")
        #expect(draft.issue(in: configuration) == nil)
        draft.setName("   ")
        #expect(draft.issue(in: configuration) == "Enter a name.")
        draft.setName(String(repeating: "a", count: 81))
        #expect(draft.issue(in: configuration) == "Use a name of 1 to 80 characters.")
        draft.setName(" Studio cache ")
        #expect(draft.issue(in: configuration) == "Each database service needs a unique name.")
        draft.setName("New")
        draft.setPort("80")
        #expect(draft.issue(in: configuration) == "Enter a port from 1024 to 65535.")
        draft.setPort("6379")
        #expect(draft.issue(in: configuration) == "Port 6379 is used by Studio cache.")
        #expect(draft.service(in: configuration) == nil)
    }

    @Test("A missing runtime blocks Add with a way forward")
    func missingRuntime() {
        let draft = DatabaseDraft.add(.mysql, in: DatabaseConfiguration())
        #expect(draft.issue(in: DatabaseConfiguration()) == "Install a MySQL runtime in Runtimes first.")
    }

    @Test("Edit keeps the ID and runtime, trims the name, and may keep its own port")
    func editKeepsIdentity() throws {
        var draft = DatabaseDraft.edit(SampleServices.studio, engine: .mysql)
        draft.setName("  Studio main ")
        let service = try #require(draft.service(in: configuration))
        #expect(service.id == SampleServices.studioID)
        #expect(service.runtimeID == SampleServices.mysql.id)
        #expect(service.name == "Studio main")
        #expect(service.port == 3306)
    }

    @Test("Restore needs a unique name and a free valid port")
    func restoreRules() {
        var draft = RestoreDraft(database: SampleServices.retained[0])
        #expect(draft.values(in: configuration)! == ("Billing archive", 5433))
        draft.name = "Reporting"
        #expect(draft.issue(in: configuration) == "Each database service needs a unique name.")
        draft.name = "Billing"
        draft.portText = "5432"
        #expect(draft.issue(in: configuration) == "Port 5432 is used by Reporting.")
    }

    @Test("Spaces alone never make a bucket name (spec F 7.2.12)")
    func blankBucketName() {
        let draft = BucketDraft(name: "   ")
        #expect(!draft.canSave(in: StorageSettings()))
        #expect(draft.issue(in: StorageSettings()) == nil)
    }

    @Test("Bucket names follow the S3 rules; a complete bucket cannot be added again")
    func bucketRules() {
        let settings = StorageSettings(buckets: SampleServices.buckets)
        #expect(BucketDraft(name: "Uploads").issue(in: settings) == BucketDraft.nameRule)
        #expect(BucketDraft(name: "a..b").issue(in: settings) == BucketDraft.nameRule)
        #expect(
            BucketDraft(name: "studio-uploads").issue(in: settings)
                == "A bucket named studio-uploads is already registered.")
        #expect(BucketDraft(name: " reports-archive ").canSave(in: settings))
        #expect(BucketDraft(name: "new-bucket").canSave(in: settings))
    }
}
