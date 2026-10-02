import Foundation

/// Edits only one explicitly marked Jerd section. All other bytes are retained.
public enum HostsDocument {
    public static func replacing(_ data: Data, hostname: String?, expectedHostname: String?) throws -> Data {
        try replacing(data, hostnames: hostname.map { [$0] } ?? [], expectedHostnames: expectedHostname.map { [$0] } ?? [])
    }

    public static func replacing(_ data: Data, hostnames: [String], expectedHostnames: [String]) throws -> Data {
        let hosts = hostnames.isEmpty ? [] : try Hostname.validatedSet(hostnames)
        let expected = expectedHostnames.isEmpty ? [] : try Hostname.validatedSet(expectedHostnames)
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else {
            throw JerdError.invalid("The hosts file is too large or is not valid UTF-8. It was not changed.")
        }
        let beginExpression = try NSRegularExpression(pattern: "(?m)^# BEGIN JERD\\r?$")
        let endExpression = try NSRegularExpression(pattern: "(?m)^# END JERD\\r?$")
        let whole = NSRange(text.startIndex..., in: text)
        let begins = beginExpression.matches(in: text, range: whole)
        let ends = endExpression.matches(in: text, range: whole)
        guard begins.count == ends.count, begins.count <= 1 else {
            throw JerdError.invalid("The Jerd hosts section has invalid markers. The hosts file was not changed.")
        }
        var section: Range<String.Index>?
        if let begin = begins.first, let end = ends.first,
           let beginRange = Range(begin.range, in: text), let endRange = Range(end.range, in: text) {
            guard beginRange.upperBound < endRange.lowerBound, !expected.isEmpty else {
                throw JerdError.invalid("An untracked Jerd hosts section already exists. It was not changed.")
            }
            let body = text[beginRange.upperBound..<endRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard body == expected.map({ "127.0.0.1 \($0)" }).joined(separator: "\n") else {
                throw JerdError.invalid("The Jerd hosts section changed outside the app. It was not overwritten.")
            }
            var start = beginRange.lowerBound
            if start > text.startIndex, text[text.index(before: start)] == "\n" { start = text.index(before: start) }
            var finish = endRange.upperBound
            if finish < text.endIndex, text[finish] == "\n" { finish = text.index(after: finish) }
            section = start..<finish
        } else if !expected.isEmpty {
            throw JerdError.invalid("The tracked Jerd hosts section is missing. No external content was changed.")
        }
        let outside = section.map { text.replacingCharacters(in: $0, with: "") } ?? text
        for host in hosts where HostsFile.hasConflict(hostname: host, contents: outside) {
            throw JerdError.invalid("The hostname \(host) already has an external hosts mapping.")
        }
        let replacement = hosts.isEmpty ? "" : "\n\(HostsFile.begin)\n" + hosts.map { "127.0.0.1 \($0)" }.joined(separator: "\n") + "\n\(HostsFile.end)\n"
        let result = section.map { text.replacingCharacters(in: $0, with: replacement) } ?? (text + replacement)
        return Data(result.utf8)
    }

    public static func containsRegistration(_ hostname: String, in data: Data) -> Bool {
        containsRegistrations([hostname], in: data)
    }

    public static func containsRegistrations(_ hostnames: [String], in data: Data) -> Bool {
        (try? replacing(data, hostnames: hostnames, expectedHostnames: hostnames)) == data
    }
}
