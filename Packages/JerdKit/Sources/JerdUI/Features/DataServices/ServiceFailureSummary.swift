import Foundation

/// The failure of a service in the form that the page banner shows: one short cause line, and
/// the last few log lines with shorter paths.
///
/// The service layer gives one reason text: a sentence (for example "The database process
/// exited.") and, after a space, up to 4 096 characters of the server log, with time stamps,
/// codes, and absolute paths. The whole text filled half the window, so the banner shows the
/// cause, an Open Log action, and at most `logLineLimit` log lines behind a disclosure.
struct ServiceFailureSummary: Equatable, Sendable {
    /// The most log lines that the banner shows. Open Log shows the full log.
    static let logLineLimit = 3
    /// A reason of one line up to this length is a message, not a message with a log tail.
    static let shortReasonLimit = 160

    /// The first sentence of the reason, or the whole reason when it is short.
    let cause: String
    /// The last non-empty log lines, oldest first, with shorter paths.
    let logLines: [String]

    /// - Parameters:
    ///   - dataFolder: The data folder of the service. A path in it shows relative to the folder,
    ///     for example `data/mysql.sock`.
    ///   - homeFolder: A path in it shows with `~`.
    init(reason: String, dataFolder: URL?, homeFolder: URL) {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: \.isNewline) || text.count > Self.shortReasonLimit else {
            cause = text
            logLines = []
            return
        }
        let (first, rest) = Self.splitFirstSentence(text)
        cause = first
        let shortener = PathShortener(dataFolder: dataFolder, homeFolder: homeFolder)
        logLines = rest.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(Self.logLineLimit)
            .map(shortener.shorten)
    }

    /// The text up to the first sentence end in the first line, and the text after it. Without a
    /// sentence end, the first line, shortened to `shortReasonLimit`, and the other lines.
    static func splitFirstSentence(_ text: String) -> (cause: String, rest: String) {
        let firstLine = text.prefix { !$0.isNewline }
        var index = firstLine.startIndex
        while let period = firstLine[index...].firstIndex(of: ".") {
            let next = firstLine.index(after: period)
            if next == firstLine.endIndex || firstLine[next].isWhitespace {
                let cause = String(firstLine[...period])
                if cause.count <= shortReasonLimit {
                    return (cause, String(text[next...]))
                }
                break
            }
            index = next
        }
        let rest = String(text[firstLine.endIndex...])
        guard firstLine.count > shortReasonLimit else { return (String(firstLine), rest) }
        return (String(firstLine.prefix(shortReasonLimit - 1)) + "…", rest)
    }

    /// Replaces the data folder and the home folder at the start of a path in a log line. Only a
    /// whole folder name matches: `/x/data` does not shorten `/x/data2`.
    struct PathShortener: Sendable {
        let dataFolder: URL?
        let homeFolder: URL

        func shorten(_ line: String) -> String {
            var result = line
            if let dataFolder {
                result = Self.replace(folder: dataFolder, with: dataFolder.lastPathComponent, in: result)
            }
            return Self.replace(folder: homeFolder, with: "~", in: result)
        }

        static func replace(folder: URL, with name: String, in line: String) -> String {
            let path = folder.standardizedFileURL.path
            guard path.count > 1 else { return line }
            let pattern = NSRegularExpression.escapedPattern(for: path) + #"(?=/|$|[\s'"`:,;)\]])"#
            return line.replacingOccurrences(
                of: pattern, with: NSRegularExpression.escapedTemplate(for: name), options: .regularExpression)
        }
    }
}
