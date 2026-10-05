import JerdSystem

/// The state of the reverse interface when the helper needs a consent.
enum ConsentChannel {
    /// The app connection is gone.
    case closed
    /// The connection exists, but its proxy is not the consent interface.
    case unavailable
    case open(any JerdTrustConsentProtocol)
}
