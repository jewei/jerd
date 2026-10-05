import Foundation
import JerdFoundation

/// Ties service data to the runtime identity that created it, through an identity marker such as
/// `runtime.json`. Data is never reused with another identity, and untracked data is never adopted.
public struct DataIdentityGuard<Identity: Codable & Equatable & Sendable>: Sendable {
    /// The refusals of this guard.
    public struct Messages: Sendable {
        /// The saved identity differs from the expected one.
        public let mismatch: JerdError
        /// Data exists, but no identity was saved for it.
        public let untracked: JerdError

        public init(mismatch: JerdError, untracked: JerdError) {
            self.mismatch = mismatch
            self.untracked = untracked
        }
    }

    public let file: URL
    public let messages: Messages

    public init(file: URL, messages: Messages) {
        self.file = file
        self.messages = messages
    }

    /// Requires the saved identity to equal `expected`. Without a saved identity, it saves
    /// `expected`, but only when `dataIsUntouched` is true.
    ///
    /// - Parameter dataIsUntouched: true when no data exists yet (for example no `data/` folder,
    ///   or an empty inbox folder). It is evaluated only when no identity is saved.
    /// - Throws: `messages.mismatch`, `messages.untracked`, or `.corrupt` for an unreadable marker.
    public func admit(_ expected: Identity, dataIsUntouched: @autoclosure () throws -> Bool) throws {
        if FileProbe.presence(at: file).mayExist {
            guard try MarkerFile.read(Identity.self, from: file) == expected else { throw messages.mismatch }
            return
        }
        guard try dataIsUntouched() else { throw messages.untracked }
        try MarkerFile.write(expected, to: file)
    }

    /// The saved identity, or nil when none is saved.
    public func saved() throws -> Identity? {
        guard FileProbe.presence(at: file).mayExist else { return nil }
        return try MarkerFile.read(Identity.self, from: file)
    }
}
