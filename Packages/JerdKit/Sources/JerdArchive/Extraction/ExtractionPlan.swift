import Foundation
import JerdFoundation

/// The pure rules of a safe extraction, applied one entry header at a time.
///
/// The plan never touches files. The extractor gives it each header in archive order, executes
/// the returned action, reports the bytes it wrote, and finally asks for the link copies.
package struct ExtractionPlan: Sendable {
    package let policy: ExtractionPolicy
    private var entryCount = 0
    private var claimedNames: Set<String> = []
    /// The first component of the first entry, when the policy strips the root.
    var root: String?
    /// Selected links and their direct targets, after root stripping.
    var links: [RelativePath: RelativePath] = [:]
    /// The bytes written for each extracted regular file.
    var fileSizes: [RelativePath: Int64] = [:]
    /// Bytes written or reserved for selected output (unselected entries do not count).
    package internal(set) var outputBytes: Int64 = 0

    package init(policy: ExtractionPolicy) {
        self.policy = policy
    }

    /// Checks one header and decides what to do with it.
    package mutating func admit(_ header: ArchiveEntryHeader) throws -> EntryAction {
        entryCount += 1
        guard entryCount <= policy.entryLimit else { throw ArchiveFailure.tooManyEntries }
        guard let stored = RelativePath(normalizing: header.path) else { throw ArchiveFailure.unsafePath }
        guard let name = try strippedName(stored) else {
            guard header.type == .directory else { throw ArchiveFailure.rootNotDirectory }
            return .skip
        }
        let target = try linkTarget(of: header, stored: stored)
        try requireSupportedType(header)
        if let size = header.size, !(0...policy.fileSizeLimit).contains(size) { throw ArchiveFailure.fileTooLarge }
        guard header.type != .directory, policy.selects(name) else { return .skip }
        guard claimedNames.insert(Self.collisionKey(name)).inserted else { throw ArchiveFailure.duplicatePath }
        if let target {
            guard let path = RelativePath(target.joined(separator: "/")) else {
                throw ArchiveFailure.linkTargetMissing
            }
            links[name] = path
            return .recordLink(path: name, target: path)
        }
        guard header.type == .regular else { throw ArchiveFailure.unsupportedType }
        return .writeFile(try reserve(name, header: header))
    }

    /// Records the bytes actually written for `write`.
    package mutating func recordWritten(_ write: FileWrite, bytes: Int64) throws {
        if write.declaredSize == nil {
            guard bytes <= policy.outputLimit - outputBytes else { throw ArchiveFailure.outputTooLarge }
            outputBytes += bytes
        }
        fileSizes[write.path] = bytes
    }

    /// The paths of every written file, sorted.
    package var writtenFiles: [RelativePath] { fileSizes.keys.sorted() }

    /// Keys that collide on a case-insensitive, Unicode-normalizing file system (`file` and `FILE`).
    package static func collisionKey(_ path: RelativePath) -> String {
        path.string.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Removes the archive root when the policy asks for it (A6). Nil means "this entry is the root".
    private mutating func strippedName(_ stored: RelativePath) throws -> RelativePath? {
        guard policy.stripsRoot else { return stored }
        let first = stored.components[0]
        if root == nil { root = first }
        guard first == root else { throw ArchiveFailure.moreThanOneRoot }
        return RelativePath(stored.components.dropFirst().joined(separator: "/"))
    }

    private func requireSupportedType(_ header: ArchiveEntryHeader) throws {
        switch header.type {
        case .regular, .directory, .symbolicLink: return
        case .other: guard header.hardlinkTarget != nil else { throw ArchiveFailure.unsupportedType }
        }
    }

    private mutating func reserve(_ name: RelativePath, header: ArchiveEntryHeader) throws -> FileWrite {
        let mode: mode_t = header.permissions & 0o111 == 0 ? 0o600 : 0o700
        let remaining = policy.outputLimit - outputBytes
        if let size = header.size {
            guard size <= remaining else { throw ArchiveFailure.outputTooLarge }
            outputBytes += size
            return FileWrite(
                path: name, mode: mode, declaredSize: size, byteLimit: size,
                limitFailure: ArchiveFailure.exceedsDeclaredSize, modificationTime: header.modificationTime)
        }
        // An entry without a recorded size may stream up to the smaller of both limits.
        let fileLimited = policy.fileSizeLimit <= remaining
        return FileWrite(
            path: name, mode: mode, declaredSize: nil, byteLimit: max(0, min(policy.fileSizeLimit, remaining)),
            limitFailure: fileLimited ? ArchiveFailure.fileTooLarge : ArchiveFailure.outputTooLarge,
            modificationTime: header.modificationTime)
    }
}
