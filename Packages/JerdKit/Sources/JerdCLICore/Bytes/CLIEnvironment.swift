/// The environment of the launcher as raw `NAME=value` entries, in their order.
///
/// The entries keep their exact bytes. The launcher changes only the planned variables, so every
/// other entry reaches PHP byte for byte. Lookups follow `getenv`: the first entry of a name wins.
package struct CLIEnvironment: Equatable, Sendable {
    /// The entries as the kernel gave them, for `execve`.
    package let entries: [[UInt8]]

    package init(entries: [[UInt8]]) {
        self.entries = entries
    }

    /// An environment from text values, sorted by name. For tests and callers without raw bytes.
    package init(_ values: [String: String]) {
        entries = values.sorted { $0.key < $1.key }.map { Array("\($0.key)=\($0.value)".utf8) }
    }

    /// The raw value of `name`, or nil when it is not set.
    package func value(_ name: String) -> [UInt8]? {
        let prefix = Array(name.utf8) + [UInt8(ascii: "=")]
        return entries.first { $0.starts(with: prefix) }.map { Array($0.dropFirst(prefix.count)) }
    }

    /// The value of `name` decoded as UTF-8 (invalid bytes repaired). Only for decisions and messages.
    package func text(_ name: String) -> String? {
        value(name).map { String(decoding: $0, as: UTF8.self) }
    }

    /// True when `name` is set, also to an empty value.
    package func contains(_ name: String) -> Bool { value(name) != nil }

    /// The environment with each changed variable set once, after the unchanged entries.
    package func setting(_ changes: [String: [UInt8]]) -> CLIEnvironment {
        let names = Set(changes.keys.map { Array($0.utf8) })
        let kept = entries.filter { entry in
            let name = Array(entry.prefix { $0 != UInt8(ascii: "=") })
            return !names.contains(name)
        }
        let added = changes.sorted { $0.key < $1.key }.map { Array($0.key.utf8) + [UInt8(ascii: "=")] + $0.value }
        return CLIEnvironment(entries: kept + added)
    }
}
