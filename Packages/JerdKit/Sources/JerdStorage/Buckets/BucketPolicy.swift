import Foundation

/// The only bucket policies that Jerd writes and accepts.
///
/// New buckets are private: they have no policy. A public bucket has exactly one grant:
/// anonymous `s3:GetObject` on its objects. Jerd never writes a policy that allows anonymous
/// writes, deletes, or listings, and it refuses to adopt any other policy.
public enum BucketPolicy {
    /// The access of one bucket.
    public enum Access: Equatable, Sendable {
        /// No anonymous access.
        case privateOnly
        /// Anonymous clients may read objects, and nothing else.
        case publicRead
    }

    /// The exact policy bytes that older builds wrote (`JSONSerialization` with sorted keys,
    /// so the slash in the resource is escaped).
    public static func publicReadDocument(bucket name: String) -> Data {
        Data(
            ("{\"Statement\":[{\"Action\":[\"s3:GetObject\"],\"Effect\":\"Allow\",\"Principal\":{\"AWS\":[\"*\"]},"
                + "\"Resource\":[\"arn:aws:s3:::\(name)\\/*\"]}],\"Version\":\"2012-10-17\"}").utf8)
    }

    /// The access that a saved policy gives, compared by meaning, not by bytes.
    ///
    /// Equivalent forms are accepted: a single statement or a list, `"*"` or `{"AWS": "*"}` or
    /// `{"AWS": ["*"]}` as the principal, a string or a list for the action and the resource, and
    /// an optional `Id` and `Sid`. No policy or an empty statement list is private.
    /// - Throws: `.invalid` for any other policy, which Jerd leaves as it is.
    public static func access(of document: Data?, bucket name: String) throws -> Access {
        guard let document else { return .privateOnly }
        guard let root = try? JSONSerialization.jsonObject(with: document) as? [String: Any],
            Set(root.keys).isSubset(of: ["Version", "Statement", "Id"]), root["Version"] as? String == "2012-10-17"
        else { throw StorageMessages.customPolicy(name) }
        let statements = (root["Statement"] as? [Any]) ?? [root["Statement"] as Any]
        if statements.isEmpty { return .privateOnly }
        guard statements.allSatisfy({ isPublicRead($0, bucket: name) }) else {
            throw StorageMessages.customPolicy(name)
        }
        return .publicRead
    }

    private static func isPublicRead(_ value: Any, bucket name: String) -> Bool {
        guard let statement = value as? [String: Any],
            Set(statement.keys).isSubset(of: ["Sid", "Effect", "Principal", "Action", "Resource"]),
            statement["Effect"] as? String == "Allow", isEveryone(statement["Principal"])
        else { return false }
        return strings(statement["Action"]) == ["s3:GetObject"]
            && strings(statement["Resource"]) == ["arn:aws:s3:::\(name)/*"]
    }

    private static func isEveryone(_ principal: Any?) -> Bool {
        if principal as? String == "*" { return true }
        guard let map = principal as? [String: Any], map.count == 1 else { return false }
        return strings(map["AWS"]) == ["*"]
    }

    /// A string or a list of strings as a set, or nil for any other form.
    private static func strings(_ value: Any?) -> Set<String>? {
        if let text = value as? String { return [text] }
        guard let list = value as? [Any], !list.isEmpty else { return nil }
        let texts = list.compactMap { $0 as? String }
        return texts.count == list.count ? Set(texts) : nil
    }
}
