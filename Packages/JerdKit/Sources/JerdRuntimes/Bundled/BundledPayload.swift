import Foundation
import JerdManifest

/// One payload in the app bundle whose receipt matches its pin.
public struct BundledPayload: Sendable {
    public let pin: RuntimePin
    public let receipt: PayloadReceipt
    /// The exact receipt bytes, which the installed folder keeps.
    public let receiptBytes: Data
    /// `RuntimePayloads/<group>/<payload ID>/`.
    public let origin: URL
}
