import Foundation

/// The single reader and writer of one saved JSON file, with its exact encoding and its backup copy.
///
/// Rules:
/// - An absent file loads as `nil`; the store never writes on load.
/// - A file that cannot be read, decoded, or validated is never overwritten. Load and save throw
///   `.corrupt`, and the bytes stay in place for inspection.
/// - Before a save replaces a valid file, its exact bytes go to `previousFile` (when one is set).
/// - Reads are bounded (`sizeLimit`), owner-checked, and refuse symbolic links.
///
/// The store does not serialize writers. Call it from the one actor that owns the file.
public struct JSONDocumentStore<Document: Codable & Sendable>: Sendable {
    /// Decodes raw bytes. Use it for versioned decoding and migration of old forms.
    public typealias Decode = @Sendable (Data, JSONDecoder) throws -> Document
    /// Structural rules that every loaded and every saved document must pass.
    public typealias Validate = @Sendable (Document) throws -> Void
    /// Extra rules for a save, which can compare the new document with the saved one (nil when absent).
    public typealias Admit = @Sendable (_ saved: Document?, _ new: Document) throws -> Void

    public let file: URL
    public let previousFile: URL?
    public let sizeLimit: Int
    public let format: JSONFileFormat
    /// A short name for messages, for example "mail settings".
    public let name: String
    private let decode: Decode
    private let validate: Validate
    private let admit: Admit

    public init(
        file: URL, previousFile: URL? = nil, sizeLimit: Int, format: JSONFileFormat, name: String,
        decode: @escaping Decode = { data, decoder in try decoder.decode(Document.self, from: data) },
        validate: @escaping Validate = { _ in },
        admit: @escaping Admit = { _, _ in }
    ) {
        self.file = file
        self.previousFile = previousFile
        self.sizeLimit = sizeLimit
        self.format = format
        self.name = name
        self.decode = decode
        self.validate = validate
        self.admit = admit
    }

    /// A copy of this store whose saves must also pass `extra`, for rules that depend on one
    /// operation (for example "this save may replace the saved runtime").
    public func admitting(_ extra: @escaping Admit) -> JSONDocumentStore {
        let admit = admit
        return JSONDocumentStore(
            file: file, previousFile: previousFile, sizeLimit: sizeLimit, format: format, name: name, decode: decode,
            validate: validate,
            admit: { saved, new in
                try admit(saved, new)
                try extra(saved, new)
            })
    }

    /// The saved document, or nil when the file is absent.
    public func load() throws -> Document? {
        try loadRecord()?.document
    }

    /// The saved document with its exact bytes, or nil when the file is absent.
    public func loadRecord() throws -> StoredDocument<Document>? {
        guard FileProbe.presence(at: file).mayExist else { return nil }
        do {
            let bytes = try AtomicFile.read(file, limit: sizeLimit)
            return StoredDocument(document: try decodeValid(bytes), bytes: bytes)
        } catch {
            throw JerdError.corrupt("Cannot read \(name). The file was preserved. \(FailureDetail.describe(error))")
        }
    }

    /// Validates, encodes, and saves `document`. Returns the exact bytes written.
    @discardableResult
    public func save(_ document: Document) throws -> Data {
        try validate(document)
        let bytes = try format.makeEncoder().encode(document)
        guard bytes.count <= sizeLimit else {
            throw JerdError.invalid("Cannot save \(name) because the new file exceeds its size limit.")
        }
        try replace(with: bytes, document: document)
        return bytes
    }

    /// Saves exact bytes, for files whose hash is recorded elsewhere. The bytes must decode and pass every rule.
    @discardableResult
    public func save(bytes: Data) throws -> Document {
        guard bytes.count <= sizeLimit else {
            throw JerdError.invalid("Cannot save \(name) because the new file exceeds its size limit.")
        }
        let document: Document
        do {
            document = try decodeValid(bytes)
        } catch {
            throw JerdError.invalid(
                "Cannot save \(name) because the new file is invalid. \(FailureDetail.describe(error))")
        }
        try replace(with: bytes, document: document)
        return document
    }

    private func decodeValid(_ bytes: Data) throws -> Document {
        let document = try decode(bytes, JSONDecoder())
        try validate(document)
        return document
    }

    private func replace(with bytes: Data, document: Document) throws {
        // A saved file that cannot be read stops the save here, so it is never overwritten.
        let saved = try loadRecord()
        try admit(saved?.document, document)
        try OwnedDirectory.create(file.deletingLastPathComponent())
        if let saved, let previousFile {
            try AtomicFile.write(saved.bytes, to: previousFile)
        }
        try AtomicFile.write(bytes, to: file)
    }
}
