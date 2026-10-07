import Foundation

/// Fetches runtime files and metadata over HTTPS. All runtime network access goes through this role.
public protocol HTTPFetching: Sendable {
    /// GETs `url` into memory.
    /// - Throws: `.invalid` when more than `limit` bytes arrive or the URL breaks the allowlist,
    ///   `.unavailable` for an HTTP or transport failure, and `CancellationError`.
    func data(from url: URL, limit: Int) async throws -> Data

    /// GETs `url` into a new private file (mode 0600) at `destination`, which must not exist.
    /// The transfer stops as soon as more than `limit` bytes arrive. A failed transfer leaves no file.
    /// - Parameter progress: whole percents as fractions 0…1, when the server states the size.
    /// - Returns: the number of bytes written.
    func download(
        from url: URL, to destination: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64
}
