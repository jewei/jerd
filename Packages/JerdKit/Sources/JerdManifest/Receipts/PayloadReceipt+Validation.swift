import JerdFoundation

extension PayloadReceipt {
    /// Schema 1, a safe payload ID, parseable versions, a valid archive digest, 1 to 50 000 safe
    /// paths with valid digests, and both executables recorded as executable files.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw Self.invalid("The payload receipt has an unsupported format version.")
        }
        guard PayloadIdentifier.isValid(id), RuntimeVersion(version) != nil, RuntimeVersion(releaseVersion) != nil,
            FileDigest.isSHA256Hex(archiveSHA256)
        else { throw Self.invalid("The payload receipt has an invalid identity.") }
        guard (1...Self.fileLimit).contains(files.count),
            files.allSatisfy({ RelativePath($0.key) != nil && FileDigest.isSHA256Hex($0.value.sha256) }),
            !files.keys.contains(Self.fileName)
        else { throw Self.invalid("The payload receipt has an invalid file list.") }
        for path in [executable] + (secondaryExecutable.map { [$0] } ?? []) {
            guard files[path.string]?.executable == true else {
                throw Self.invalid("The payload receipt does not record its executable: \(path).")
            }
        }
        if let signing {
            guard Self.isTeamID(signing.teamID),
                FileDigest.isSHA256Hex(signing.sourceReceiptSHA256)
            else { throw Self.invalid("The payload receipt has an invalid signing record.") }
        }
    }

    /// An Apple team ID: 10 characters `A-Z` or `0-9`.
    public static func isTeamID(_ text: String) -> Bool {
        text.utf8.count == 10 && text.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
    }
}
