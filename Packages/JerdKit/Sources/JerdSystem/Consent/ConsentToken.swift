import Foundation

/// The proof that one operation opened a consent scope.
public struct ConsentToken: Hashable, Sendable {
    private let id = UUID()
}
