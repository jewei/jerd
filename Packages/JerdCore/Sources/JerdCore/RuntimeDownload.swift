import Foundation
import CryptoKit

enum RuntimeDownload {
    static let hosts: Set<String> = ["api.github.com", "github.com", "raw.githubusercontent.com",
        "release-assets.githubusercontent.com", "objects.githubusercontent.com", "codeload.github.com",
        "getcomposer.org", "repo.packagist.org", "packagist.org", "download.redis.io",
        "dev.mysql.com", "cdn.mysql.com", "downloads.mysql.com", "repo.mysql.com"]

    static func validate(_ url: URL) throws {
        guard url.scheme == "https", let host = url.host?.lowercased(), hosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
            throw JerdError.invalid("The update source has an unsupported download URL.")
        }
    }

    static func file(_ url: URL, to destination: URL, limit: Int64,
                     progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try validate(url)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 900
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let policy = DownloadPolicy(limit: limit, progress: progress)
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Jerd/0.1 runtime-updates", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request, delegate: policy)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JerdError.unavailable(code == 403 || code == 429 ?
                "The update source limit was reached. Try again later." : "The update source returned HTTP \(code).")
        }
        guard let finalURL = response.url else { throw JerdError.invalid("The update response has no URL.") }
        try validate(finalURL)
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size > 0, Int64(size) <= limit else { throw JerdError.invalid("The download exceeds its size limit or is empty.") }
        try Task.checkCancellation()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    static func digest(_ file: URL) throws -> String {
        try sha256(file).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ file: URL, suffix: Data = Data()) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let hadData = try autoreleasepool {
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { return false }
                hash.update(data: data)
                return true
            }
            if !hadData { break }
        }
        hash.update(data: suffix)
        return Data(hash.finalize())
    }
    static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

private final class DownloadPolicy: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastPercent = -1
    init(limit: Int64, progress: @escaping @Sendable (Double) -> Void) { self.limit = limit; self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? RuntimeDownload.validate(url)) != nil else { completionHandler(nil); return }
        var next = request
        next.setValue(nil, forHTTPHeaderField: "Authorization")
        next.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(next)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel(); return }
        if totalBytesExpectedToWrite > 0 {
            let percent = min(100, Int(totalBytesWritten * 100 / totalBytesExpectedToWrite))
            let changed = lock.withLock {
                guard percent != lastPercent else { return false }
                lastPercent = percent
                return true
            }
            if changed { progress(Double(percent) / 100) }
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

actor RuntimeMetadata {
    private var cache: [URL: (Date, Data)] = [:]
    func data(_ url: URL) async throws -> Data {
        if let (date, data) = cache[url], Date().timeIntervalSince(date) < 300 { return data }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-metadata-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await RuntimeDownload.file(url, to: temporary, limit: 8_000_000)
        let data = try Data(contentsOf: temporary)
        cache[url] = (Date(), data)
        return data
    }
    func text(_ url: URL) async throws -> String {
        guard let string = String(data: try await data(url), encoding: .utf8) else { throw JerdError.invalid("The update source has invalid text.") }
        return string
    }
}
