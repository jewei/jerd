/// Parses the output of `php-fpm -n -m`.
public enum PHPModuleList {
    /// The trimmed, non-empty lines after `[PHP Modules]` up to the next `[` section, unique and sorted.
    public static func parse(_ output: String) -> [String] {
        var inSection = false
        var modules: Set<String> = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "[PHP Modules]" {
                inSection = true
                continue
            }
            if line.hasPrefix("[") { inSection = false }
            if inSection, !line.isEmpty { modules.insert(line) }
        }
        return modules.sorted()
    }
}
