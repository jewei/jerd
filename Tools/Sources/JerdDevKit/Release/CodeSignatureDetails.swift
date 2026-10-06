/// The facts of a signature that the release checks, from the standard error of `codesign -d --verbose=4`.
struct CodeSignatureDetails: Equatable, Sendable {
    var identifier: String?
    var teamIdentifier: String?
    /// The CodeDirectory flags include `runtime` (the hardened runtime).
    var hasHardenedRuntime = false
    /// A secure timestamp exists (`Timestamp=`; an ad hoc or untimed signature has `Signed Time=` or nothing).
    var hasTimestamp = false

    static func parse(_ output: String) -> CodeSignatureDetails {
        var details = CodeSignatureDetails()
        for line in output.split(separator: "\n").map(String.init) {
            if let value = value(of: "Identifier", in: line) {
                details.identifier = value
            } else if let value = value(of: "TeamIdentifier", in: line) {
                details.teamIdentifier = value
            } else if line.hasPrefix("Timestamp=") {
                details.hasTimestamp = true
            } else if line.hasPrefix("CodeDirectory "), let flags = flags(in: line) {
                details.hasHardenedRuntime = flags.split(separator: ",").contains("runtime")
            }
        }
        return details
    }

    private static func value(of key: String, in line: String) -> String? {
        line.hasPrefix("\(key)=") ? String(line.dropFirst(key.count + 1)) : nil
    }

    /// `flags=0x10000(runtime)` gives `runtime`.
    private static func flags(in line: String) -> Substring? {
        guard let start = line.range(of: "flags=")?.upperBound, let open = line[start...].firstIndex(of: "("),
            let close = line[open...].firstIndex(of: ")")
        else { return nil }
        return line[line.index(after: open)..<close]
    }
}
