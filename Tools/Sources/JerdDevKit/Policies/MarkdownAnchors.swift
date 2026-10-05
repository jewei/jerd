/// The page anchors of a Markdown document as GitHub makes them: one for each ATX heading (`# Title`)
/// outside fenced code, and one for each HTML `id` or `name` attribute. A repeated heading gets `-1`,
/// `-2`, and so on. Setext headings (text over `===`) are not read.
enum MarkdownAnchors {
    private static var heading: Regex<(Substring, Substring)> {
        #/^ {0,3}#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$/#
    }

    private static var htmlAnchor: Regex<(Substring, Substring)> {
        #/\b(?:id|name)="([^"]+)"/#
    }

    private static var link: Regex<(Substring, Substring)> {
        #/!?\[([^\]]*)\]\([^)]*\)/#
    }

    static func anchors(in markdown: String) -> Set<String> {
        var anchors: Set<String> = []
        var counts: [String: Int] = [:]
        var inFence = false
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            anchors.formUnion(line.matches(of: htmlAnchor).map { String($0.output.1) })
            guard let match = line.wholeMatch(of: heading) else { continue }
            let base = slug(String(match.output.1))
            let count = counts[base, default: 0]
            counts[base] = count + 1
            anchors.insert(count == 0 ? base : "\(base)-\(count)")
        }
        return anchors
    }

    /// GitHub's rule: keep the text of links, lowercase, remove every character that is not a letter,
    /// a mark, a number, a connector such as `_`, a space, or a hyphen, then change spaces to hyphens.
    static func slug(_ heading: String) -> String {
        let text = heading.replacing(link) { $0.output.1 }.lowercased()
        let kept = text.unicodeScalars.filter { scalar in
            let properties = scalar.properties
            switch properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark, .connectorPunctuation:
                return true
            default:
                return properties.isAlphabetic || properties.numericType != nil || scalar == " " || scalar == "-"
            }
        }
        return String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
    }
}
