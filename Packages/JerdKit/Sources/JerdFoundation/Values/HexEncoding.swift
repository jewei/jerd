import Foundation

/// Hexadecimal text for bytes, and checks for hexadecimal text.
public enum HexEncoding {
    /// The letter case of the digits a–f.
    public enum LetterCase: Sendable {
        case lower
        case upper
    }

    /// Two hexadecimal digits for each byte.
    public static func string(_ bytes: some Sequence<UInt8>, letterCase: LetterCase = .lower) -> String {
        let digits = Array(letterCase == .lower ? "0123456789abcdef".utf8 : "0123456789ABCDEF".utf8)
        var characters: [UInt8] = []
        for byte in bytes {
            characters.append(digits[Int(byte >> 4)])
            characters.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: characters, as: UTF8.self)
    }

    /// True when `text` has exactly `length` characters, each `0-9` or a letter of the given case.
    public static func isHex(_ text: String, length: Int, letterCase: LetterCase = .lower) -> Bool {
        let letters: ClosedRange<UInt8> = letterCase == .lower ? 97...102 : 65...70
        return text.utf8.count == length && text.utf8.allSatisfy { (48...57).contains($0) || letters.contains($0) }
    }
}
