import Foundation

/// The HTTP answer of the loopback test server to one request head. Pure, so every rule has a test.
///
/// Only `GET` and `HEAD` of one plain file name in the served folder are answered: no subfolders, no
/// hidden files, and no `..`, so a request cannot read anything else on the Mac.
enum StaticFileResponse {
    /// The largest request head that the server reads.
    static let headLimit = 16_384

    /// True when `data` holds a complete request head.
    static func isComplete(_ data: Data) -> Bool {
        data.range(of: Data("\r\n\r\n".utf8)) != nil
    }

    /// The response bytes for a request head.
    /// - Parameter read: the bytes of a plain file name in the folder, or nil when it does not exist.
    static func response(to head: Data, read: (String) -> Data?) -> Data {
        guard head.count <= headLimit, let line = String(data: head, encoding: .utf8)?.split(separator: "\r\n").first
        else { return status(400, "Bad Request") }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return status(400, "Bad Request") }
        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else { return status(405, "Method Not Allowed") }
        guard let name = fileName(inTarget: String(parts[1])), let body = read(name) else {
            return status(404, "Not Found")
        }
        let headers = [
            "HTTP/1.1 200 OK", "Content-Type: \(contentType(of: name))", "Content-Length: \(body.count)",
            "Connection: close", "", "",
        ].joined(separator: "\r\n")
        return Data(headers.utf8) + (method == "HEAD" ? Data() : body)
    }

    /// The file name of a target such as `/appcast.xml`, or nil for any other form.
    static func fileName(inTarget target: String) -> String? {
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard path.hasPrefix("/") else { return nil }
        let name = String(path.dropFirst())
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !name.isEmpty, !name.hasPrefix("."), name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return name
    }

    static func contentType(of name: String) -> String {
        name.hasSuffix(".xml") ? "application/xml" : "application/octet-stream"
    }

    static func status(_ code: Int, _ reason: String) -> Data {
        Data("HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}
