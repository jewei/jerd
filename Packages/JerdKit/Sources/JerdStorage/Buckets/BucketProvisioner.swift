/// Brings one saved bucket intent to a verified bucket on the running service.
///
/// Steps: create the bucket when it is absent → apply the access (a public-read policy, or no
/// policy) → read the policy back and compare its meaning → `HEAD` the bucket. Every step can
/// run again, so a failed setup is retried from the start with the same intent. The caller marks
/// the record complete only after `provision` returns.
struct BucketProvisioner: Sendable {
    let client: S3Client

    /// Requires that RustFS has no bucket with `name`, before a new intent is saved.
    func requireAbsent(_ name: String) async throws {
        guard try await !client.bucketExists(name) else { throw StorageMessages.alreadyInRustFS(name) }
    }

    func provision(_ bucket: StorageBucket) async throws {
        if try await !client.bucketExists(bucket.name) { try await client.createBucket(bucket.name) }
        let wanted: BucketPolicy.Access = bucket.publicRead ? .publicRead : .privateOnly
        switch wanted {
        case .publicRead:
            try await client.putPolicy(BucketPolicy.publicReadDocument(bucket: bucket.name), on: bucket.name)
        case .privateOnly:
            try await client.deletePolicy(of: bucket.name)
        }
        let applied = try BucketPolicy.access(of: try await client.policy(of: bucket.name), bucket: bucket.name)
        guard applied == wanted else { throw StorageMessages.accessUnverified }
        guard try await client.bucketExists(bucket.name) else { throw StorageMessages.bucketUnconfirmed }
    }
}
