import Foundation

/// The status and body of one answer.
public struct S3Response: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    /// True for a 2xx status.
    public var succeeded: Bool { (200..<300).contains(status) }
}
