import JerdFoundation

extension BuildReceipt {
    /// Rule I14: schema 1, parseable versions, a valid archive digest, 1 to 50 000 safe paths with
    /// valid digests, and both executables recorded.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
            RuntimeVersion(version) != nil, RuntimeVersion(releaseVersion) != nil,
            FileDigest.isSHA256Hex(archiveSHA256),
            (1...Self.fileLimit).contains(files.count),
            files[executable] != nil,
            secondaryExecutable.map({ files[$0] != nil }) ?? true,
            files.allSatisfy({ RelativePath($0.key) != nil && FileDigest.isSHA256Hex($0.value) })
        else { throw Self.invalidReceipt }
    }

    /// The current build folder name: `<kind>-<releaseVersion>-<arch>-<archiveSHA256>`.
    public static func folderName(
        kind: RuntimeKind, releaseVersion: String, architecture: CPUArchitecture, archiveSHA256: String
    ) -> String {
        "\(legacyFolderName(kind: kind, releaseVersion: releaseVersion, architecture: architecture))-\(archiveSHA256)"
    }

    /// The legacy build folder name without a digest: `<kind>-<releaseVersion>-<arch>`. Still read and reused.
    public static func legacyFolderName(
        kind: RuntimeKind, releaseVersion: String, architecture: CPUArchitecture
    ) -> String {
        "\(kind.rawValue)-\(releaseVersion)-\(architecture.rawValue)"
    }

    /// Rule I15: a build folder must have the current or the legacy name of its receipt.
    public func matchesFolderName(_ name: String, architecture: CPUArchitecture) -> Bool {
        let legacy = Self.legacyFolderName(kind: kind, releaseVersion: releaseVersion, architecture: architecture)
        return name == legacy || name == "\(legacy)-\(archiveSHA256)"
    }
}
