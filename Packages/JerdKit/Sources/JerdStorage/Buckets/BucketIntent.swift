/// What a Save of a bucket does with the registered buckets.
enum BucketIntent: Equatable, Sendable {
    /// No record exists. RustFS must not have the bucket, and a new intent is saved.
    case new(StorageBucket)
    /// An unfinished intent with the same access. Setup continues.
    case resume(StorageBucket)
    /// An unfinished intent with another access. The intent is saved with the new access first.
    case change(StorageBucket)

    /// The bucket that the setup brings to completion.
    var bucket: StorageBucket {
        switch self {
        case .new(let bucket), .resume(let bucket), .change(let bucket): bucket
        }
    }

    /// The intent of saving `name` with `publicRead` in `settings`.
    /// - Throws: `.invalid` for an invalid name or a complete bucket with that name.
    static func of(name: String, publicRead: Bool, in settings: StorageSettings) throws -> BucketIntent {
        try BucketName.validate(name)
        guard let saved = settings.bucket(name) else {
            return .new(StorageBucket(name: name, publicRead: publicRead))
        }
        guard !saved.setupComplete else { throw StorageMessages.alreadyRegistered(name) }
        guard saved.publicRead != publicRead else { return .resume(saved) }
        return .change(StorageBucket(name: name, publicRead: publicRead))
    }
}
