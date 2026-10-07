import Foundation
import JerdFoundation

/// Why a transfer stopped early. The transfer delegate records it before it cancels the task.
enum TransferFailure: Equatable, Sendable {
    /// More bytes than the limit arrived, or the server announced more.
    case tooLarge
    /// The final response did not have status 200. 0 means not an HTTP response.
    case status(Int)
    /// A redirect or the final URL broke the host allowlist.
    case unsupportedURL
    /// The response had no URL.
    case missingURL
    /// No byte arrived.
    case empty
    /// Writing the destination file failed with this `errno`.
    case write(Int32)

    /// The user-visible error.
    var error: JerdError {
        switch self {
        case .tooLarge, .empty: .invalid("The download exceeds its size limit or is empty.")
        case .status(let code) where code == 403 || code == 429:
            .unavailable("The update source limit was reached. Try again later.")
        case .status(let code): .unavailable("The update source returned HTTP \(code).")
        case .unsupportedURL: HostAllowlist.unsupported
        case .missingURL: .invalid("The update response has no URL.")
        case .write(let code): .unavailable("Cannot save the download (\(SystemError.describe(code))).")
        }
    }
}
