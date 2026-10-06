import Foundation

/// Parsers of the S3 XML answers that Jerd reads.
///
/// External entities are never resolved. Element names are compared without their namespace.
enum S3XMLParsers {
    /// The bucket names of a `ListAllMyBucketsResult` answer.
    ///
    /// A name that breaks Jerd's bucket rules (for example one made in the RustFS console with
    /// a reserved suffix) is left out, not an error: one such bucket must not stop storage from
    /// starting. Jerd never registers or changes such a bucket.
    /// - Throws: `.processFailed` when the answer is not a bucket list.
    static func bucketNames(in data: Data) throws -> Set<String> {
        let delegate = BucketListDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), delegate.isBucketList else { throw StorageMessages.invalidBucketList }
        return delegate.names.filter(BucketName.isValid)
    }
}
