import Foundation

/// The text that tells why Save is off. The sheets show it at the top, so the reason is
/// visible also when the control that it names is below the visible part of the form.
enum SaveRequirement {
    /// "To save, enter a name and a hostname." for the empty fields, in form order.
    static func enter(_ missing: [String]) -> String {
        "To save, enter \(listed(missing))."
    }

    /// "a", "a and b", or "a, b, and c".
    static func listed(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + (items.last ?? "")
        }
    }

    /// The labels of the fields whose trimmed text is empty.
    static func missing(_ fields: [(text: String, label: String)]) -> [String] {
        fields.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.label)
    }
}
