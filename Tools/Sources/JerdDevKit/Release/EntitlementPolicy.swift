import Foundation

/// The reviewed entitlements of runtime binaries. A release keeps no other entitlement, so no debug or
/// task-access right survives into a signed payload.
enum EntitlementPolicy {
    static let allowJIT = "com.apple.security.cs.allow-jit"
    static let allowUnsignedMemory = "com.apple.security.cs.allow-unsigned-executable-memory"
    static let disableLibraryValidation = "com.apple.security.cs.disable-library-validation"
    static let getTaskAllow = "com.apple.security.get-task-allow"

    static let reviewed: Set<String> = [allowJIT, allowUnsignedMemory, disableLibraryValidation]

    /// The entitlements of the new signature of a runtime file.
    /// - Parameters:
    ///   - existing: the XML of `codesign -d --entitlements - --xml`; empty when the file has none.
    ///   - isPHP: the PHP CLI and PHP-FPM, whose PCRE and OPcache JIT allocate executable memory.
    /// - Throws: `DevFailure.checkFailed` for any unreviewed key or a value that is not `true`.
    static func entitlements(existing: Data, isPHP: Bool, file: String) throws -> [String: Bool] {
        var result = try decode(existing, file: file)
        guard Set(result.keys).isSubset(of: reviewed), result.values.allSatisfy({ $0 }) else {
            throw DevFailure.checkFailed("\(file) has unreviewed runtime entitlements.")
        }
        if isPHP {
            result[allowJIT] = true
            result[allowUnsignedMemory] = true
        }
        return result
    }

    /// True when the entitlements XML grants `get-task-allow`, which only debug builds may have.
    static func grantsDebugging(_ data: Data, file: String) throws -> Bool {
        let object = try decodeObject(data, file: file)
        return (object[getTaskAllow] as? Bool) == true
    }

    static func plist(_ entitlements: [String: Bool]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
    }

    private static func decode(_ data: Data, file: String) throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        for (key, value) in try decodeObject(data, file: file) {
            guard let flag = value as? Bool else {
                throw DevFailure.checkFailed("\(file) has the entitlement \(key) with a value that is not a boolean.")
            }
            result[key] = flag
        }
        return result
    }

    private static func decodeObject(_ data: Data, file: String) throws -> [String: Any] {
        guard !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 }) else { return [:] }
        let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = object as? [String: Any] else {
            throw DevFailure.checkFailed("The entitlements of \(file) cannot be read.")
        }
        return dictionary
    }
}
