import Foundation

/// A decoded document together with the exact bytes that were read, for hashes and backups.
public struct StoredDocument<Document: Sendable>: Sendable {
    public let document: Document
    public let bytes: Data

    public init(document: Document, bytes: Data) {
        self.document = document
        self.bytes = bytes
    }
}

extension StoredDocument: Equatable where Document: Equatable {}
