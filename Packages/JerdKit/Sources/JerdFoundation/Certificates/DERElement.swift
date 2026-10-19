import Foundation

/// Reads ASN.1 DER values strictly: definite lengths only, minimal length forms, and no bytes
/// after the last value. A certificate that breaks a rule is invalid, never guessed at.
public struct DERElement: Equatable, Sendable {
    public let tag: UInt8
    public let content: Data

    /// The values inside a constructed element, in order.
    public func children() throws -> [DERElement] {
        guard tag & 0x20 != 0 else { throw JerdError.invalid("A DER value is not constructed.") }
        return try DERElement.all(in: content)
    }

    /// Every value in `data`, which must end exactly after the last one.
    public static func all(in data: Data) throws -> [DERElement] {
        let bytes = [UInt8](data)
        var index = 0
        var elements: [DERElement] = []
        while index < bytes.count {
            let (element, next) = try read(bytes, at: index)
            elements.append(element)
            index = next
        }
        return elements
    }

    /// The one value that `data` holds.
    public static func single(in data: Data) throws -> DERElement {
        let elements = try all(in: data)
        guard elements.count == 1 else { throw JerdError.invalid("The DER data holds more than one value.") }
        return elements[0]
    }

    private static func read(_ bytes: [UInt8], at start: Int) throws -> (DERElement, Int) {
        let invalid = JerdError.invalid("The DER data is not valid.")
        guard start + 2 <= bytes.count, bytes[start] & 0x1F != 0x1F else { throw invalid }
        var index = start + 2
        var length = Int(bytes[start + 1])
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), index + count <= bytes.count, bytes[index] != 0 else { throw invalid }
            length = bytes[index..<index + count].reduce(0) { $0 << 8 | Int($1) }
            guard length >= 0x80 else { throw invalid }
            index += count
        }
        guard length <= bytes.count - index else { throw invalid }
        let element = DERElement(tag: bytes[start], content: Data(bytes[index..<index + length]))
        return (element, index + length)
    }
}
