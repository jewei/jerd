import Foundation
import JerdFoundation

/// The marker of completed data initialization, such as `initialized.json`. Partial data from an
/// interrupted initialization is never initialized again.
public struct InitializationMarker<Marker: Codable & Equatable & Sendable>: Sendable {
    /// What a start must do with the data.
    public enum Status: Equatable, Sendable {
        /// The marker matches and the data is complete.
        case initialized
        /// No marker and no data: initialization may run.
        case uninitialized
    }

    /// The refusals of this marker.
    public struct Messages: Sendable {
        /// The marker differs from the expected one, or the data that it proves is missing.
        public let mismatch: JerdError
        /// Data exists without a marker. Nil when such data is allowed (the service creates it).
        public let interrupted: JerdError?

        public init(mismatch: JerdError, interrupted: JerdError?) {
            self.mismatch = mismatch
            self.interrupted = interrupted
        }
    }

    public let file: URL
    public let messages: Messages

    public init(file: URL, messages: Messages) {
        self.file = file
        self.messages = messages
    }

    /// Decides the status from the marker and the data.
    ///
    /// - Parameters:
    ///   - expected: the marker that the current data must have.
    ///   - dataIsComplete: true when the data that the marker proves exists with the right type.
    ///   - dataMayExist: true unless the absence of data is proven.
    public func status(expected: Marker, dataIsComplete: Bool, dataMayExist: Bool) throws -> Status {
        if FileProbe.presence(at: file).mayExist {
            guard try MarkerFile.read(Marker.self, from: file) == expected, dataIsComplete else {
                throw messages.mismatch
            }
            return .initialized
        }
        if dataMayExist, let interrupted = messages.interrupted { throw interrupted }
        return .uninitialized
    }

    /// Saves the marker after a successful initialization or start.
    public func write(_ marker: Marker) throws {
        try MarkerFile.write(marker, to: file)
    }
}
