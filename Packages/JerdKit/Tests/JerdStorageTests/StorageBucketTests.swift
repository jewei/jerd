import Foundation
import JerdFoundation
import JerdServiceKit
import Testing

@testable import JerdStorage

@Suite struct StorageBucketTests {
    @Test func savingABucketStartsStorageAndCompletesAPrivateBucket() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.addBucket(name: "app-uploads", publicRead: false)
        let snapshot = await manager.snapshot()
        #expect(snapshot.processID != nil)
        #expect(snapshot.settings.buckets == [StorageBucket(name: "app-uploads", setupComplete: true)])
        #expect(snapshot.availableBuckets == ["app-uploads"])
        #expect(snapshot.status(of: snapshot.settings.buckets[0]) == .ready)
        #expect(harness.server.current.policies["app-uploads"] == nil)
        await #expect(throws: StorageMessages.alreadyRegistered("app-uploads")) {
            try await manager.addBucket(name: "app-uploads", publicRead: false)
        }
        try await manager.stop()
    }

    @Test func aPublicBucketGetsOnlyTheReadPolicy() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.addBucket(name: "public.assets", publicRead: true)
        #expect(
            harness.server.current.policies["public.assets"] == BucketPolicy.publicReadDocument(bucket: "public.assets")
        )
        #expect(await manager.snapshot().settings.bucket("public.assets")?.setupComplete == true)
        try await manager.stop()
    }

    @Test func aServerThatNormalizesThePolicyStillVerifies() async throws {
        let harness = try await StorageHarness()
        harness.server.update {
            $0.normalize = { _ in
                Data(
                    #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::public.assets/*"}]}"#
                        .utf8)
            }
            $0.deleteWithoutPolicyStatus = 404
        }
        let manager = try await harness.loadedManager()
        try await manager.addBucket(name: "public.assets", publicRead: true)
        try await manager.addBucket(name: "private-files", publicRead: false)
        #expect(await manager.snapshot().settings.buckets.allSatisfy(\.setupComplete))
        try await manager.stop()
    }

    @Test func anExistingServerBucketIsNeverAdopted() async throws {
        let harness = try await StorageHarness()
        harness.server.update { $0.buckets = ["app-uploads"] }
        let manager = try await harness.loadedManager()
        await #expect(throws: StorageMessages.alreadyInRustFS("app-uploads")) {
            try await manager.addBucket(name: "app-uploads", publicRead: false)
        }
        #expect(await manager.snapshot().settings.buckets.isEmpty)
        try await manager.stop()
    }

    @Test func aFailedSetupKeepsTheIntentAndRetryFinishesIt() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        harness.server.update { $0.failures["PUT /public.assets?policy="] = 500 }
        await #expect(throws: StorageMessages.httpStatus(500)) {
            try await manager.addBucket(name: "public.assets", publicRead: true)
        }
        let pending = try #require(await manager.snapshot().settings.bucket("public.assets"))
        #expect(!pending.setupComplete && pending.publicRead)
        #expect(await manager.snapshot().status(of: pending) == .setupIncomplete)
        try await manager.stop()
        let restarted = harness.manager()
        _ = try await restarted.load()
        try await restarted.retryBucket("public.assets")
        #expect(await restarted.snapshot().settings.bucket("public.assets")?.setupComplete == true)
        await #expect(throws: StorageMessages.onlyUnfinishedRetry) { try await restarted.retryBucket("public.assets") }
        await #expect(throws: StorageMessages.onlyUnfinishedRetry) { try await restarted.retryBucket("unknown") }
        try await restarted.stop()
    }

    @Test func aFailedExistenceCheckSavesNoIntent() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        harness.server.update { $0.failures["HEAD /public.assets"] = 500 }
        await #expect(throws: StorageMessages.httpStatus(500)) {
            try await manager.addBucket(name: "public.assets", publicRead: true)
        }
        #expect(await manager.snapshot().settings.buckets.isEmpty)
        try await manager.stop()
    }

    @Test func savingAnUnfinishedBucketWithOtherAccessUpdatesTheIntent() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        harness.server.update { $0.failures["PUT /assets?policy="] = 500 }
        await #expect(throws: (any Error).self) { try await manager.addBucket(name: "assets", publicRead: true) }
        try await manager.addBucket(name: "assets", publicRead: false)
        #expect(
            await manager.snapshot().settings.bucket("assets") == StorageBucket(name: "assets", setupComplete: true))
        #expect(harness.server.current.policies["assets"] == nil)
        try await manager.stop()
    }

    @Test func aMissingCompleteBucketIsReportedAndNeverCreatedAgain() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.addBucket(name: "app-uploads", publicRead: false)
        harness.server.update { $0.buckets = [] }
        try await manager.refreshBuckets()
        let snapshot = await manager.snapshot()
        #expect(snapshot.status(of: snapshot.settings.buckets[0]) == .missing)
        await #expect(throws: StorageMessages.onlyUnfinishedRetry) { try await manager.retryBucket("app-uploads") }
        #expect(!harness.server.current.buckets.contains("app-uploads"))
        try await manager.stop()
        await #expect(throws: StorageMessages.startBeforeBuckets) { try await manager.refreshBuckets() }
    }

    @Test func serverBucketsWithInvalidNamesDoNotStopStorage() async throws {
        let harness = try await StorageHarness()
        harness.server.update { $0.foreignNames = ["console--x-s3", "Upper"] }
        let manager = try await harness.loadedManager()
        try await manager.start()
        let snapshot = await manager.snapshot()
        #expect(snapshot.processID != nil && snapshot.availableBuckets.isEmpty)
        try await manager.stop()
    }
}
