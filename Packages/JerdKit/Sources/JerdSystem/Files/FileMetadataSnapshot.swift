import Darwin
import Foundation
import JerdFoundation

/// The `stat` fields, ACL text, and extended attributes of an open file, read with bounded sizes.
///
/// Two snapshots match when the identity, type, mode, owner, group, link count, flags, size,
/// modification time, ACL, and attributes are equal. The change time is compared only on request,
/// because an exchange changes it.
struct FileMetadataSnapshot: Sendable {
    /// The total budget for the ACL text, attribute names, and attribute values (bytes).
    static let budget = 1_048_576

    let info: stat
    let acl: Data
    let attributes: [String: Data]

    /// Reads the metadata of `descriptor`. The change time must not move during the read.
    static func capture(_ descriptor: Int32) throws -> FileMetadataSnapshot {
        guard let info = DescriptorIO.status(of: descriptor), let acl = aclText(descriptor),
            let attributes = extendedAttributes(descriptor, budget: budget - acl.count),
            let after = DescriptorIO.status(of: descriptor), sameChangeTime(info, after)
        else { throw JerdError.invalid("Cannot inspect hosts metadata safely.") }
        return FileMetadataSnapshot(info: info, acl: acl, attributes: attributes)
    }

    func matches(_ other: FileMetadataSnapshot, includingChangeTime: Bool = false) -> Bool {
        let lhs = info
        let rhs = other.info
        return lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_mode == rhs.st_mode
            && lhs.st_uid == rhs.st_uid && lhs.st_gid == rhs.st_gid && lhs.st_nlink == rhs.st_nlink
            && lhs.st_flags == rhs.st_flags && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && (!includingChangeTime || Self.sameChangeTime(lhs, rhs))
            && acl == other.acl && attributes == other.attributes
    }

    private static func sameChangeTime(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    /// The ACL text, empty when the file has no ACL, or nil on failure.
    private static func aclText(_ descriptor: Int32) -> Data? {
        guard let acl = acl_get_fd(descriptor) else { return errno == ENOENT ? Data() : nil }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length) else { return nil }
        defer { acl_free(text) }
        guard (0...budget).contains(length) else { return nil }
        return Data(bytes: text, count: length)
    }

    /// Every attribute name and value within `budget` bytes, or nil on failure.
    private static func extendedAttributes(_ descriptor: Int32, budget: Int) -> [String: Data]? {
        let length = flistxattr(descriptor, nil, 0, 0)
        guard (0...budget).contains(length) else { return nil }
        var names = [CChar](repeating: 0, count: length)
        guard length == 0 || flistxattr(descriptor, &names, names.count, 0) == length else { return nil }
        var attributes: [String: Data] = [:]
        var remaining = budget - length
        for name in names.split(separator: 0) {
            let key = String(decoding: name.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let count = fgetxattr(descriptor, key, nil, 0, 0, 0)
            guard count >= 0, count <= remaining else { return nil }
            var value = Data(count: count)
            let read = value.withUnsafeMutableBytes { fgetxattr(descriptor, key, $0.baseAddress, count, 0, 0) }
            guard read == count else { return nil }
            attributes[key] = value
            remaining -= count
        }
        return attributes
    }
}
