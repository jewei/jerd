import Foundation

/// A small JSON tree for the generated Caddy files, written with `JSONSerialization` so the
/// output keeps Apple's exact pretty format (two spaces, `" : "`).
indirect enum JSONValue: Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case boolean(Bool)

    /// The Foundation object that `JSONSerialization` writes.
    var foundationObject: Any {
        switch self {
        case .object(let members): members.mapValues(\.foundationObject)
        case .array(let items): items.map(\.foundationObject)
        case .string(let text): text
        case .integer(let number): number
        case .boolean(let flag): flag
        }
    }

    /// Serializes with the given options. The top level must be an object or an array.
    func serialized(_ options: JSONSerialization.WritingOptions) throws -> Data {
        try JSONSerialization.data(withJSONObject: foundationObject, options: options)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .integer(value) }
    init(booleanLiteral value: Bool) { self = .boolean(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }

    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
