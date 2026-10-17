import Foundation

/// The proof that one operation opened a consent scope.
package struct ConsentToken: Hashable, Sendable {
    private let id = UUID()
}
