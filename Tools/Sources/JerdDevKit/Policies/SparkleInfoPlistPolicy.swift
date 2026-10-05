import Foundation

/// The Sparkle keys in `Apps/Jerd/Resources/Info.plist`. Each key and value type is exact: no automatic
/// checks or installs by default, no profiling, signed feeds only, and archives checked before extraction.
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
        ("SUEnableAutomaticChecks", .bool(false)),
        ("SUAutomaticallyUpdate", .bool(false)),
        ("SUAllowsAutomaticUpdates", .bool(false)),
        ("SUEnableSystemProfiling", .bool(false)),
        ("SUVerifyUpdateBeforeExtraction", .bool(true)),
        ("SURequireSignedFeed", .bool(true)),
        ("SUSignedFeedFailureExpirationInterval", .integer(0)),
    ]

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
        let known = Set(requiredValues.map(\.key))
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
