import Foundation
import JerdFoundation
import JerdServiceKit

extension StorageManager {
    /// Saves a bucket and sets it up. It starts storage when no process runs.
    ///
    /// A new name is saved as an unfinished intent only after RustFS proves that no such bucket
    /// exists. An unfinished intent continues, also with another `publicRead`, which is saved
    /// first. The record is complete only after `BucketProvisioner` verified the bucket.
    public func addBucket(name: String, publicRead: Bool) async throws {
        try await coordinator.exclusive { coordinator in
            let intent = try BucketIntent.of(name: name, publicRead: publicRead, in: coordinator.settings)
            _ = try await self.runningService(startingIfNeeded: true, in: coordinator)
            let (client, launch) = try self.client(in: coordinator)
            let provisioner = BucketProvisioner(client: client)
            switch intent {
            case .new(let bucket):
                try await provisioner.requireAbsent(bucket.name)
                var next = coordinator.settings
                next.buckets.append(bucket)
                try coordinator.save(next)
            case .change(let bucket):
                try coordinator.save(Self.replacing(bucket, in: coordinator.settings))
            case .resume:
                break
            }
            try await self.complete(intent.bucket, with: provisioner, launch: launch, in: coordinator)
        }
    }

    /// Continues the setup of an unfinished bucket. It starts storage when no process runs.
    public func retryBucket(_ name: String) async throws {
        try await coordinator.exclusive { coordinator in
            guard let bucket = coordinator.settings.bucket(name), !bucket.setupComplete else {
                throw StorageMessages.onlyUnfinishedRetry
            }
            _ = try await self.runningService(startingIfNeeded: true, in: coordinator)
            let (client, launch) = try self.client(in: coordinator)
            try await self.complete(bucket, with: BucketProvisioner(client: client), launch: launch, in: coordinator)
        }
    }

    /// Lists the buckets of the running service again.
    public func refreshBuckets() async throws {
        try await coordinator.exclusive { coordinator in
            _ = try await self.runningService(startingIfNeeded: false, in: coordinator)
            let (client, launch) = try self.client(in: coordinator)
            self.launch.replaceNames(try await client.listBuckets(), of: launch)
        }
    }

    /// Verifies `bucket`, then saves it as complete. A failure keeps the unfinished record.
    private func complete(
        _ bucket: StorageBucket, with provisioner: BucketProvisioner, launch id: UUID,
        in coordinator: isolated Coordinator
    ) async throws {
        try await provisioner.provision(bucket)
        var done = bucket
        done.setupComplete = true
        try coordinator.save(Self.replacing(done, in: coordinator.settings))
        launch.insert(bucket.name, of: id)
    }

    private static func replacing(_ bucket: StorageBucket, in settings: StorageSettings) -> StorageSettings {
        var next = settings
        next.buckets = next.buckets.map { $0.name == bucket.name ? bucket : $0 }
        return next
    }
}
