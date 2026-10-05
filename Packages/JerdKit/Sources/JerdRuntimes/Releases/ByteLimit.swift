/// The byte bound of a download.
public enum ByteLimit: Hashable, Sendable {
    /// The publisher states the exact size. A different size is an error.
    case exact(Int64)
    /// The publisher states no size. The download may not exceed this many bytes.
    case atMost(Int64)

    /// The largest accepted byte count.
    public var limit: Int64 {
        switch self {
        case .exact(let value), .atMost(let value): value
        }
    }
}
