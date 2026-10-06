import Foundation

/// Whether `add` created the keychain item, so that a failed setup can delete only its own item.
enum KeychainAddOutcome: Equatable, Sendable {
    case added
    case alreadyPresent
}
