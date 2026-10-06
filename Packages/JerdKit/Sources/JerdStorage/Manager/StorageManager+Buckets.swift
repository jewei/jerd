import JerdFoundation
import JerdServiceKit

extension StorageManager {
    /// Saves a bucket and sets it up. It starts storage when no process runs.
    ///
    /// A new name is saved as an unfinished intent only after RustFS proves that no such bucket
    /// exists. An unfinished intent continues, also with another `publicRead`, which is saved
    /// first. The record is complete only after `BucketProvisioner` verified the bucket.
    public func addBucket(name: String, publicRead: Bool) async throws {
        try await exclusive {
            let intent = try BucketIntent.of(name: name, publicRead: publicRead, in: settings)
            _ = try await runningService(startingIfNeeded: true)
            let provisioner = BucketProvisioner(client: try client())
            switch intent {
            case .new(let bucket):
                try await provisioner.requireAbsent(bucket.name)
                var next = settings
                next.buckets.append(bucket)
                try save(next)
            case .change(let bucket):
                try save(replacing(bucket, in: settings))
            case .resume:
                break
            }
            try await complete(intent.bucket, with: provisioner)
        }
    }

    /// Continues the setup of an unfinished bucket. It starts storage when no process runs.
    public func retryBucket(_ name: String) async throws {
        try await exclusive {
            guard let bucket = settings.bucket(name), !bucket.setupComplete else {
                throw StorageMessages.onlyUnfinishedRetry
            }
            _ = try await runningService(startingIfNeeded: true)
            try await complete(bucket, with: BucketProvisioner(client: try client()))
        }
    }

    /// Lists the buckets of the running service again.
    public func refreshBuckets() async throws {
        try await exclusive {
            _ = try await runningService(startingIfNeeded: false)
            listed.replace(with: try await client().listBuckets())
        }
    }

    /// Verifies `bucket`, then saves it as complete. A failure keeps the unfinished record.
    private func complete(_ bucket: StorageBucket, with provisioner: BucketProvisioner) async throws {
        try await provisioner.provision(bucket)
        var done = bucket
        done.setupComplete = true
        try save(replacing(done, in: settings))
        listed.insert(bucket.name)
    }

    private func replacing(_ bucket: StorageBucket, in settings: StorageSettings) -> StorageSettings {
        var next = settings
        next.buckets = next.buckets.map { $0.name == bucket.name ? bucket : $0 }
        return next
    }
}
