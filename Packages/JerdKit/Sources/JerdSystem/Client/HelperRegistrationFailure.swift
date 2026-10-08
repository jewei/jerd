import Foundation
import JerdFoundation
import ServiceManagement

/// The cause of a failed `SMAppService` call, and the message that the user can act on. Pure, so
/// every cause has a table test. A raw Cocoa text such as "Operation not permitted" never reaches
/// the user.
enum HelperRegistrationFailure: Equatable, Sendable {
    /// The old helper process was still exiting. A short wait and a new attempt fix it.
    case transient
    /// The user turned the helper off, or macOS waits for approval in Login Items & Extensions.
    case disabled
    /// The app or helper signature is not valid for `SMAppService`.
    case invalidSignature
    /// The app bundle has no helper plist or program at the expected place.
    case missingHelper
    /// The helper was not registered; `unregister` treats this as done.
    case notRegistered
    /// Anything else, with its domain and code for the report.
    case other(domain: String, code: Int)

    /// The value of `SMAppServiceErrorDomain` (its symbol needs macOS 15).
    static let serviceDomain = "SMAppServiceErrorDomain"
    /// The value of the deprecated `kSMErrorDomainFramework`.
    static let frameworkDomain = "kSMErrorDomainFramework"

    static func classify(_ error: any Error) -> HelperRegistrationFailure {
        let error = error as NSError
        if error.code == Int(EPERM), [NSPOSIXErrorDomain, serviceDomain].contains(error.domain) {
            return .transient
        }
        guard [serviceDomain, frameworkDomain].contains(error.domain) else {
            return .other(domain: error.domain, code: error.code)
        }
        switch error.code {
        case Int(kSMErrorLaunchDeniedByUser), Int(kSMErrorJobMustBeEnabled): return .disabled
        case Int(kSMErrorInvalidSignature), Int(kSMErrorToolNotValid): return .invalidSignature
        case Int(kSMErrorJobPlistNotFound), Int(kSMErrorInvalidPlist): return .missingHelper
        case Int(kSMErrorJobNotFound): return .notRegistered
        default: return .other(domain: error.domain, code: error.code)
        }
    }

    /// The error that the app shows. A `JerdError` stays as it is: it is already actionable.
    /// A transient failure that did not end after the retries counts as a disabled helper, the
    /// state that macOS leaves after a refused registration.
    static func error(for error: any Error) -> JerdError {
        if let error = error as? JerdError { return error }
        switch classify(error) {
        case .transient, .disabled: return disabledError
        case .invalidSignature:
            return .unavailable(
                "macOS refused the signature of the Jerd helper. Install Jerd again from its disk image into "
                    + "Applications, then open it.")
        case .missingHelper:
            return .unavailable(
                "Jerd cannot find its system helper in the app. Install Jerd again from its disk image into "
                    + "Applications, then open it.")
        case .notRegistered:
            return JerdError.unavailable("The Jerd helper is not registered. Click Reconnect Helper… to register it.")
                .with(.reconnectHelper)
        case .other(let domain, let code):
            return JerdError.unavailable(
                "macOS could not register the Jerd helper. Quit Jerd, open it again, then click Reconnect Helper…. "
                    + "If it fails again, restart the Mac. (\(domain) \(code))"
            ).with(.reconnectHelper)
        }
    }

    /// The helper is off in Login Items & Extensions. Host entries and certificate trust stay.
    static var disabledError: JerdError {
        JerdError.unavailable(
            "The Jerd helper is turned off. Turn on Jerd in System Settings → General → Login Items & Extensions, "
                + "then try again. Host entries and certificate settings stay."
        ).with(.openLoginItems)
    }
}
