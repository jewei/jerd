/// The `errno` value of a failed descriptor operation.
public struct DescriptorIOFailure: Error, Equatable, Sendable {
    public let code: Int32
    public init(code: Int32) { self.code = code }
}
