import JerdFoundation

/// The rules for the aliases of one site: valid `.test` names, none equal to the hostname or to
/// each other, saved lowercase and sorted, so the saved form and the Caddy routes are stable.
public enum SiteAliases {
    /// The names in the editor text, which separates them with commas, spaces, or line breaks.
    public static func parse(_ text: String) -> [String] {
        text.split { $0 == "," || $0.isWhitespace }.map { $0.lowercased() }
    }

    /// The editor text for saved aliases.
    public static func text(_ aliases: [String]) -> String {
        aliases.joined(separator: ", ")
    }

    /// - Returns: The aliases, lowercase and sorted.
    /// - Throws: `.invalid` for an invalid name, a name equal to `hostname`, or a repeated name.
    public static func validate(_ aliases: [String], hostname: String) throws -> [String] {
        var result: [String] = []
        for text in aliases {
            let alias: String
            do {
                alias = try HostnamePolicy.validate(text.lowercased()).value
            } catch let error as JerdError {
                throw JerdError.invalid("The alias \(text) is not valid. \(error.message)")
            }
            guard alias != hostname else {
                throw JerdError.invalid("Remove the alias that is the same as the hostname.")
            }
            guard !result.contains(alias) else { throw JerdError.invalid("Enter the alias \(alias) only once.") }
            result.append(alias)
        }
        return result.sorted()
    }
}
