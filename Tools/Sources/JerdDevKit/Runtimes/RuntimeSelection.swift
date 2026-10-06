import JerdManifest

/// What `./dev runtimes prepare` prepares: payload groups and the XZ support library.
///
/// RustFS needs the reviewed XZ library, so the storage group always selects XZ too. An empty list
/// selects everything. Names are case-insensitive; `Support/XZ`, `support`, and `xz` name the library.
struct RuntimeSelection: Equatable, Sendable {
    /// The payload groups, in the order of `PayloadGroup.allCases`.
    var groups: [PayloadGroup]
    /// True when the XZ support library is built (or its earlier build is verified).
    var buildsXZ: Bool

    static let all = RuntimeSelection(groups: PayloadGroup.allCases, buildsXZ: true)

    /// The names that `--help` and error messages show.
    static let names = PayloadGroup.allCases.map(\.rawValue) + ["xz"]

    /// Parses the command arguments.
    /// - Throws: a usage failure for an unknown name.
    static func parse(_ arguments: [String]) throws -> RuntimeSelection {
        guard !arguments.isEmpty else { return .all }
        var groups: Set<PayloadGroup> = []
        var buildsXZ = false
        for argument in arguments {
            let name = argument.lowercased()
            if ["xz", "support", "support/xz"].contains(name) {
                buildsXZ = true
            } else if let group = PayloadGroup(rawValue: name) {
                groups.insert(group)
            } else {
                throw DevFailure.usage(
                    "Unknown runtime group \"\(argument)\". Use one or more of: \(names.joined(separator: ", ")).")
            }
        }
        return RuntimeSelection(
            groups: PayloadGroup.allCases.filter(groups.contains), buildsXZ: buildsXZ || groups.contains(.storage))
    }
}
