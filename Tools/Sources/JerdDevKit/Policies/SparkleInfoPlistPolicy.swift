import Foundation

/// The Sparkle keys in `Apps/Jerd/Resources/Info.plist`. Each key and value type is exact: no automatic
/// installs, no profiling, signed feeds only, and archives checked before extraction. The automatic check
/// key must be absent, so Sparkle asks the user once whether to check for updates automatically.
enum SparkleInfoPlistPolicy {
    static let file = "Apps/Jerd/Resources/Info.plist"

    /// A property list value with its exact type. `<integer>0</integer>` is not `<false/>`.
    enum Value: Equatable, CustomStringConvertible {
        case string(String)
        case bool(Bool)
        case integer(Int)

        var description: String {
            switch self {
            case .string(let value): "string \"\(value)\""
            case .bool(let value): "boolean \(value)"
            case .integer(let value): "integer \(value)"
            }
        }
    }

    static let requiredValues: [(key: String, value: Value)] = [
        ("SUFeedURL", .string("$(JERD_UPDATE_FEED_URL)")),
        ("SUPublicEDKey", .string("$(JERD_UPDATE_PUBLIC_KEY)")),
        ("SUAutomaticallyUpdate", .bool(false)),
        ("SUAllowsAutomaticUpdates", .bool(false)),
        ("SUEnableSystemProfiling", .bool(false)),
        ("SUVerifyUpdateBeforeExtraction", .bool(true)),
        ("SURequireSignedFeed", .bool(true)),
        ("SUSignedFeedFailureExpirationInterval", .integer(0)),
    ]

    /// Keys that must not be set. Without `SUEnableAutomaticChecks`, Sparkle asks the user at the second
    /// launch whether to check automatically; a fixed value would decide for every user.
    static let absentKeys = ["SUEnableAutomaticChecks"]

    /// The findings for each key of `absentKeys` that the dictionary sets.
    static func absentKeyFindings(_ dictionary: [String: Any], file: String) -> [PolicyFinding] {
        absentKeys.filter { dictionary[$0] != nil }.map {
            PolicyFinding(file: file, message: "\($0) must be absent, so Sparkle asks the user whether to check.")
        }
    }

    static func findings(plistData: Data) -> [PolicyFinding] {
        let decoded = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        guard let dictionary = decoded as? [String: Any] else {
            return [PolicyFinding(file: file, message: "The file is not a property list dictionary.")]
        }
        var findings: [PolicyFinding] = []
        for (key, required) in requiredValues {
            let actual = dictionary[key].flatMap(value(of:))
            if actual != required {
                let found = actual.map { "has \($0)" } ?? "is missing"
                findings.append(PolicyFinding(file: file, message: "\(key) \(found); it must be \(required)."))
            }
        }
        findings += absentKeyFindings(dictionary, file: file)
        let known = Set(requiredValues.map(\.key) + absentKeys)
        for key in dictionary.keys.sorted() where key.hasPrefix("SU") && !known.contains(key) {
            findings.append(PolicyFinding(file: file, message: "\(key) is not an approved Sparkle setting."))
        }
        return findings
    }

    /// Reads a property list object with its exact type. Booleans and numbers share `NSNumber`.
    static func value(of object: Any) -> Value? {
        if let string = object as? String {
            return .string(string)
        }
        guard let number = object as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        return CFNumberIsFloatType(number) ? nil : .integer(number.intValue)
    }
}
